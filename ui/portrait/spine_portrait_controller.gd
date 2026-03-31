## Spine 立绘控制器
## 管理单个角色立绘的皮肤切换、表情状态、说话动画、过渡动画
## 参照项目 AnimDriverSpine 规范（2026-03-08 官方标准）：
##   - 信号 animation_completed 挂在 SpineSprite 上
##   - set_animation 使用 Signature 2: (name, loop, track)
##   - 不调用 clearTrack()，替换直接调 set_animation()
class_name SpinePortraitController
extends Node

## 关联的 SpineSprite 节点（在编辑器或外部赋值）
@export var spine_sprite: SpineSprite

## 初始皮肤（_ready 后自动应用，空字符串=不设置）
@export var initial_skin: StringName = &""

## 当前稳定状态（idle_loop / angry_loop 等）
var current_stable_state: StringName = &"idle_loop"

## 当前是否处于说话动画中
var _in_talk: bool = false
## 当前说话动画是否为自含式（如 angry_talk_loop）
var _talk_is_combined: bool = false
## 当前说话对应的情绪
var _current_talk_emotion: StringName = &"idle"

## API 签名（同 AnimDriverSpine 检测逻辑）
var _api_sig: int = 2  # 默认 Signature 2: (name, loop, track)

## 待执行的动画队列 [[name, loop], ...]
## 用于在 animation_completed 时继续播放下一段
var _anim_queue: Array[Array] = []


func _ready() -> void:
	if spine_sprite == null:
		push_warning("[SpinePortraitController] spine_sprite 未设置：%s" % name)
		return
	call_deferred("_deferred_ready")


func _deferred_ready() -> void:
	if spine_sprite == null:
		return

	# 探测 API 签名
	var anim_state: Object = _get_anim_state()
	if anim_state != null:
		_detect_sig(anim_state)

	# 连接 animation_completed 信号（在 SpineSprite 上，不在 AnimationState 上）
	if spine_sprite.has_signal("animation_completed"):
		spine_sprite.animation_completed.connect(_on_anim_completed)
	elif spine_sprite.has_signal("animation_ended"):
		spine_sprite.animation_ended.connect(_on_anim_completed)

	# 应用初始皮肤
	if initial_skin != &"":
		set_skin(initial_skin)

	# 播放默认待机动画
	_play(&"idle_loop", true)
	current_stable_state = &"idle_loop"


## ── 公开接口 ──

## 播放动画链（由 DialogueBubbleLayer 调用）
## chain: ExpressionTransitionResolver.AnimChain
func apply_chain(chain: ExpressionTransitionResolver.AnimChain) -> void:
	_in_talk = false
	_anim_queue.clear()

	if chain.entries.is_empty():
		_play(chain.stable_state, true)
		current_stable_state = chain.stable_state
		return

	# 找出 talk 状态
	var talk_anims_check: Array[StringName] = [&"talk_loop", &"idle_to_talk"]
	for e: Array in chain.entries:
		var n: StringName = e[0]
		var is_talk: bool = str(n).ends_with("_talk_loop") or talk_anims_check.has(n)
		if is_talk:
			_in_talk = true
			_talk_is_combined = str(n).ends_with("_talk_loop")
			_current_talk_emotion = ExpressionTransitionResolver._stable_to_emotion(chain.stable_state)
			break

	# 播放第一段，其余入队
	var first: Array = chain.entries[0]
	_play(first[0], first[1])
	for i: int in range(1, chain.entries.size()):
		_anim_queue.append(chain.entries[i])
	# 稳定态最终兜底入队（loop=true），在 text_finished 时不走此路径
	_anim_queue.append([chain.stable_state, true])

	current_stable_state = chain.stable_state


## 文字打字完成时：退出说话动画，回到稳定 loop
func on_text_finished() -> void:
	if not _in_talk:
		return
	_in_talk = false
	_anim_queue.clear()

	var exit_chain: ExpressionTransitionResolver.AnimChain = ExpressionTransitionResolver.resolve_exit_talk(
		_current_talk_emotion,
		_talk_is_combined,
		has_animation
	)
	if exit_chain.entries.is_empty():
		_play(exit_chain.stable_state, true)
	else:
		var first: Array = exit_chain.entries[0]
		_play(first[0], first[1])
		for i: int in range(1, exit_chain.entries.size()):
			_anim_queue.append(exit_chain.entries[i])
		_anim_queue.append([exit_chain.stable_state, true])
	current_stable_state = exit_chain.stable_state


## 强制推进（等同于 text_finished）
func on_force_advance() -> void:
	on_text_finished()


## 直接播放稳定状态（无过渡）
func play_stable(emotion: StringName) -> void:
	var stable: StringName = ExpressionTransitionResolver.emotion_to_stable(emotion)
	_in_talk = false
	_anim_queue.clear()
	_play(stable, true)
	current_stable_state = stable


## 切换皮肤
func set_skin(skin_name: StringName) -> void:
	if spine_sprite == null or skin_name == &"" or skin_name == &"Default":
		return
	var skeleton: Object = null
	if spine_sprite.has_method("get_skeleton"):
		skeleton = spine_sprite.get_skeleton()
	elif spine_sprite.has_method("getSkeleton"):
		skeleton = spine_sprite.getSkeleton()
	if skeleton == null:
		return
	if skeleton.has_method("set_skin_by_name"):
		skeleton.set_skin_by_name(str(skin_name))
	elif skeleton.has_method("setSkinByName"):
		skeleton.setSkinByName(str(skin_name))
	if skeleton.has_method("set_slots_to_setup_pose"):
		skeleton.set_slots_to_setup_pose()
	elif skeleton.has_method("setSlotsToSetupPose"):
		skeleton.setSlotsToSetupPose()


## 检查动画是否存在（供 ExpressionTransitionResolver 回调）
## 优先通过 SpineSkeletonDataResource 查询；无法查询时默认返回 true（兜底策略）
func has_animation(anim_name: StringName) -> bool:
	if spine_sprite == null:
		return false
	var skel_data: SpineSkeletonDataResource = spine_sprite.skeleton_data_res
	if skel_data == null:
		return false
	# 尝试 get_animation_names() 获取动画名列表
	if skel_data.has_method("get_animation_names"):
		var names = skel_data.get_animation_names()
		return names.has(str(anim_name))
	# 兜底：返回 true（Spine 会在播放时给出警告，但不会崩溃）
	return true


## ── 内部 ──

func _play(anim_name: StringName, loop: bool) -> void:
	if spine_sprite == null:
		return
	var anim_state: Object = _get_anim_state()
	if anim_state == null:
		return
	var name_str: String = str(anim_name)
	if anim_state.has_method("set_animation"):
		if _api_sig == 1:
			anim_state.set_animation(0, name_str, loop)
		else:
			anim_state.set_animation(name_str, loop, 0)
	elif anim_state.has_method("setAnimation"):
		if _api_sig == 1:
			anim_state.setAnimation(0, name_str, loop)
		else:
			anim_state.setAnimation(name_str, loop, 0)


func _get_anim_state() -> Object:
	if spine_sprite == null:
		return null
	if spine_sprite.has_method("get_animation_state"):
		return spine_sprite.get_animation_state()
	if spine_sprite.has_method("getAnimationState"):
		return spine_sprite.getAnimationState()
	return null


func _detect_sig(anim_state: Object) -> void:
	for m: Dictionary in anim_state.get_method_list():
		var mname: String = m.get("name", "")
		if mname != "set_animation" and mname != "setAnimation":
			continue
		var args: Array = m.get("args", [])
		if args.size() < 3:
			continue
		if int(args[0].get("type", -1)) == TYPE_INT:
			_api_sig = 1
			return
		_api_sig = 2
		return


## animation_completed 信号回调（可变参数兼容不同 Spine 版本）
func _on_anim_completed(_entry = null, _arg2 = null, _arg3 = null) -> void:
	if _anim_queue.is_empty():
		return
	var next: Array = _anim_queue.pop_front()
	var next_name: StringName = next[0]
	var next_loop: bool = next[1]
	_play(next_name, next_loop)
