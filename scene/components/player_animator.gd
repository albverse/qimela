extends Node
class_name PlayerAnimator
## 玩家Spine2D动画控制器
## 独立于player.gd，专门处理动画逻辑
## 
## 使用方式：
## 1. 将此脚本挂载到 Player/Components/Animator 节点
## 2. 在Inspector中设置 spine_path 指向 SpineSprite 节点
## 3. 代码中通过 player.animator.play_xxx() 调用

# ============================================================
# 动画名称配置（可在Inspector覆盖）
# ============================================================
@export_group("基础动画")
@export var anim_idle: StringName = &"idle"              ## 静止站立（需求统一为 idle）
@export var anim_walk: StringName = &"walk"              ## 行走
@export var anim_run: StringName = &"run"                ## 奔跑（双击方向键）

@export_group("跳跃动画")
@export var anim_jump_up: StringName = &"jump_up"        ## 跳跃起跳瞬间
@export var anim_jump_loop: StringName = &"jump_loop"    ## 空中下落循环
@export var anim_jump_down: StringName = &"jump_down"    ## 落地

@export_group("锁链动画 - 发射")
@export var anim_chain_r: StringName = &"chain_R"        ## 右手发射锁链
@export var anim_chain_l: StringName = &"chain_L"        ## 左手发射锁链
@export var anim_chain_lr: StringName = &"chain_LR"      ## 双手同时发射（0.2秒内连击）

@export_group("锁链动画 - 取消")
@export var anim_chain_r_cancel: StringName = &"chain_R_cancel"   ## 取消右手锁链
@export var anim_chain_l_cancel: StringName = &"chain_L_cancel"   ## 取消左手锁链
@export var anim_chain_lr_cancel: StringName = &"chain_LR_cancel" ## 取消双手锁链

@export_group("Spine节点配置")
@export var spine_path: NodePath = ^"../Visual/SpineSprite"  ## SpineSprite节点路径

@export_group("骨骼锚点名称")
@export var bone_chain_anchor_l: StringName = &"chain_anchor_l"  ## 左手锁链发射点骨骼
@export var bone_chain_anchor_r: StringName = &"chain_anchor_r"  ## 右手锁链发射点骨骼

# ============================================================
# 运行时变量
# ============================================================
var _player: Player = null
var _spine: Node = null  # SpineSprite
var _current_anim: StringName = &""
var _current_track: int = 0
var _is_one_shot_playing: bool = false
var _one_shot_timer: float = 0.0
var _has_completion_signal: bool = false

@export_group("一次性动画回收")
@export var one_shot_fallback_timeout: float = 1.2  ## 仅在无completion信号时启用的兜底时长

# 动画队列：一次性动画播完后回到的动画
var _return_anim: StringName = &""

# 连击检测
var _last_fire_time: float = -1.0
const DOUBLE_CLICK_WINDOW: float = 0.2  # 双击时间窗口

# ============================================================
# 初始化
# ============================================================

func _ready() -> void:
	_player = _find_player()
	if _player == null:
		push_error("[PlayerAnimator] Player not found in parent chain.")
		return
	
	print("[PlayerAnimator] Initializing... spine_path=%s" % spine_path)
	_spine = get_node_or_null(spine_path)
	if _spine == null:
		push_error("[PlayerAnimator] SpineSprite not found at: %s" % spine_path)
	else:
		print("[PlayerAnimator] SpineSprite found: %s (type=%s)" % [_spine.name, _spine.get_class()])
		# 连接动画完成信号
		if _spine.has_signal("animation_completed"):
			_spine.connect("animation_completed", _on_animation_completed)
			_has_completion_signal = true
			print("[PlayerAnimator] Connected to signal: animation_completed")
		elif _spine.has_signal("animation_complete"):
			_spine.connect("animation_complete", _on_animation_completed)
			_has_completion_signal = true
			print("[PlayerAnimator] Connected to signal: animation_complete")
		else:
			push_warning("[PlayerAnimator] No animation completion signal found")
	
	# 初始播放idle
	print("[PlayerAnimator] Playing initial animation: %s" % anim_idle)
	play_idle()
	set_process(true)


func _process(delta: float) -> void:
	# 兜底：仅在没有completion信号时启用超时回收，避免提前截断真实一次性动画
	if _has_completion_signal:
		return
	if not _is_one_shot_playing:
		return
	if _one_shot_timer <= 0.0:
		return
	_one_shot_timer -= delta
	if _one_shot_timer <= 0.0:
		_finish_one_shot()


func _find_player() -> Player:
	var p: Node = self
	while p != null and not (p is Player):
		p = p.get_parent()
	return p as Player


# ============================================================
# 动画播放核心函数
# ============================================================

func _play(anim_name: StringName, loop: bool = true, track: int = 0, return_to_idle: bool = false) -> void:
	"""播放Spine动画
	Args:
		anim_name: 动画名称
		loop: 是否循环
		track: 动画轨道（0=主轨道）
		return_to_idle: 播完后是否自动回到idle
	"""
	if _spine == null:
		push_error("[PlayerAnimator] _spine is null! Cannot play animation.")
		return
	
	# ✅ 验证动画名称（关键修复）
	if anim_name == StringName("") or anim_name == &"":
		push_error("[PlayerAnimator] Animation name is empty! Check Inspector settings.")
		return
	
	var anim_name_str := String(anim_name)
	if anim_name_str.is_empty() or anim_name_str == "0":
		push_error("[PlayerAnimator] Invalid animation name: '%s'. Check Inspector settings." % anim_name_str)
		return
	
	# 避免重复播放同一循环动画
	if loop and anim_name == _current_anim and track == _current_track:
		return
	
	_current_anim = anim_name
	_current_track = track
	_is_one_shot_playing = not loop
	_one_shot_timer = one_shot_fallback_timeout if (not loop and not _has_completion_signal) else 0.0
	_return_anim = anim_idle if return_to_idle else &""
	
	# 获取AnimationState并播放
	if not _spine.has_method("get_animation_state"):
		push_error("[PlayerAnimator] SpineSprite missing get_animation_state method!")
		return
	
	var anim_state: Object = _spine.call("get_animation_state")
	if anim_state == null:
		push_error("[PlayerAnimator] AnimationState is null!")
		return
	
	if anim_state.has_method("set_animation"):
		print("[PlayerAnimator] Playing: %s (loop=%s, track=%d)" % [anim_name_str, loop, track])
		# Spine Godot绑定参数顺序：set_animation(animation_name, loop, track)
		# 若把 track/loop 传反，会出现：循环动画只播一次、一次性动画时序异常
		anim_state.set_animation(anim_name_str, loop, track)
	else:
		push_error("[PlayerAnimator] AnimationState missing set_animation method!")


func _on_animation_completed(_track_entry: Variant) -> void:
	"""动画播放完毕回调"""
	_finish_one_shot()


func _finish_one_shot() -> void:
	"""一次性动画结束后的统一收尾（信号/超时共用）"""
	if not _is_one_shot_playing and _return_anim == &"":
		return
	_is_one_shot_playing = false
	_one_shot_timer = 0.0
	if _return_anim != &"":
		var return_to := _return_anim
		_return_anim = &""
		_play(return_to, true, 0, false)


# ============================================================
# 公开动画接口 - 基础动作
# ============================================================

func play_idle() -> void:
	"""播放静止站立动画"""
	_play(anim_idle, true)


func play_walk() -> void:
	"""播放行走动画"""
	_play(anim_walk, true)


func play_run() -> void:
	"""播放奔跑动画"""
	_play(anim_run, true)


# ============================================================
# 公开动画接口 - 跳跃
# ============================================================

func play_jump_up() -> void:
	"""播放跳跃起跳动画（一次性，播完进入jump_loop）"""
	_return_anim = anim_jump_loop
	_play(anim_jump_up, false)


func play_jump_loop() -> void:
	"""播放空中下落循环动画"""
	_play(anim_jump_loop, true)


func play_jump_down() -> void:
	"""播放落地动画（一次性，播完回到idle）"""
	_play(anim_jump_down, false, 0, true)


# ============================================================
# 公开动画接口 - 锁链发射
# ============================================================

func play_chain_fire(slot: int, other_slot_state: int) -> void:
	"""播放锁链发射动画
	Args:
		slot: 发射的锁链槽位（0=右手优先，1=左手）
		other_slot_state: 另一条锁链的状态（用于判断是否播放双手动画）
	"""
	var now := Time.get_ticks_msec() / 1000.0
	var is_double_click := (now - _last_fire_time) < DOUBLE_CLICK_WINDOW
	_last_fire_time = now
	
	# 如果0.2秒内连击且另一条链刚发射，播放双手动画
	if is_double_click and other_slot_state == 1:  # FLYING = 1
		_play(anim_chain_lr, false, 0, true)
		return
	
	# 根据槽位选择左手或右手动画
	# 注意：slot 0 对应右手，slot 1 对应左手
	var anim := anim_chain_r if slot == 0 else anim_chain_l
	_play(anim, false, 0, true)


func play_chain_fire_right() -> void:
	"""播放右手发射锁链动画"""
	_play(anim_chain_r, false, 0, true)


func play_chain_fire_left() -> void:
	"""播放左手发射锁链动画"""
	_play(anim_chain_l, false, 0, true)


func play_chain_fire_both() -> void:
	"""播放双手发射锁链动画"""
	_play(anim_chain_lr, false, 0, true)


# ============================================================
# 公开动画接口 - 锁链取消
# ============================================================

func play_chain_cancel(right_active: bool, left_active: bool) -> void:
	"""播放取消锁链动画
	Args:
		right_active: 右手锁链是否激活（非IDLE）
		left_active: 左手锁链是否激活（非IDLE）
	"""
	if right_active and left_active:
		_play(anim_chain_lr_cancel, false, 0, true)
	elif right_active:
		_play(anim_chain_r_cancel, false, 0, true)
	elif left_active:
		_play(anim_chain_l_cancel, false, 0, true)
	# 都不激活则不播放


func play_chain_cancel_right() -> void:
	"""播放取消右手锁链动画"""
	_play(anim_chain_r_cancel, false, 0, true)


func play_chain_cancel_left() -> void:
	"""播放取消左手锁链动画"""
	_play(anim_chain_l_cancel, false, 0, true)


func play_chain_cancel_both() -> void:
	"""播放取消双手锁链动画"""
	_play(anim_chain_lr_cancel, false, 0, true)


# ============================================================
# 骨骼锚点位置获取（处理翻转）
# ============================================================

func get_chain_anchor_position(use_right_hand: bool) -> Vector2:
	"""获取锁链发射点的世界坐标
	Args:
		use_right_hand: 是否使用右手锚点
	Returns:
		世界坐标位置
	"""
	if _spine == null or _player == null:
		return _get_fallback_hand_position(use_right_hand)
	


	var bone_name := bone_chain_anchor_r if use_right_hand else bone_chain_anchor_l
	
	# 尝试从Spine获取骨骼位置
	if _spine.has_method("get_skeleton"):
		var skeleton: Object = _spine.call("get_skeleton")
		if skeleton != null and skeleton.has_method("find_bone"):
			var bone: Object = skeleton.call("find_bone", String(bone_name))
			if bone != null and bone.has_method("get_world_x") and bone.has_method("get_world_y"):
				var local_x: float = bone.call("get_world_x")
				var local_y: float = bone.call("get_world_y")
				# 转换为全局坐标
				var spine_node := _spine as Node2D
				if spine_node != null:
					return spine_node.to_global(Vector2(local_x, local_y))
	
	# 回退：使用Marker2D
	return _get_fallback_hand_position(use_right_hand)


func _get_fallback_hand_position(use_right_hand: bool) -> Vector2:
	"""回退方案：使用Marker2D获取手部位置"""
	if _player == null:
		return Vector2.ZERO
	
	var hand_path := _player.hand_r_path if use_right_hand else _player.hand_l_path
	var hand: Node2D = _player.get_node_or_null(hand_path) as Node2D
	if hand != null:
		return hand.global_position
	
	return _player.global_position


# ============================================================
# 状态查询
# ============================================================

func get_current_anim() -> StringName:
	"""获取当前播放的动画名称"""
	return _current_anim


func is_one_shot_playing() -> bool:
	"""是否正在播放一次性动画（用于阻止移动逻辑覆盖）"""
	return _is_one_shot_playing


func is_playing(anim_name: StringName) -> bool:
	"""检查是否正在播放指定动画"""
	return _current_anim == anim_name


func has_spine() -> bool:
	"""检查是否有可用的SpineSprite"""
	return _spine != null
