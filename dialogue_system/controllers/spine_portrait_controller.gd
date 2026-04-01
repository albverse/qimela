extends Node
class_name SpinePortraitController

## Spine 立绘控制器
## 职责：接收结构化状态指令，执行皮肤切换、表情 loop / talk / transition
## 不决定何时进入下一句文本，不直接读取对话 tags

const LOG_PREFIX: String = "[SpinePortrait]"

signal talk_finished()
signal transition_finished()

@export var debug_log: bool = false

## 当前稳定态动画名
var current_stable_anim: StringName = &"idle_loop"

## 内部动画驱动器
var _anim_driver: AnimDriverSpine = null
var _spine_sprite: Node = null
var _available_animations: PackedStringArray = PackedStringArray()

## 状态追踪
var _is_talking: bool = false
var _pending_stable: StringName = &""
var _pending_transition_to_talk: bool = false
var _transition_resolver: ExpressionTransitionResolver = null

## 当前动画链
var _current_chain: ExpressionTransitionResolver.AnimationChain = null


func setup(spine_sprite: Node) -> void:
	_spine_sprite = spine_sprite
	if _spine_sprite == null:
		push_error("%s spine_sprite is null!" % LOG_PREFIX)
		return

	# 初始化动画驱动器
	_anim_driver = AnimDriverSpine.new()
	_anim_driver.debug_log = debug_log
	add_child(_anim_driver)
	_anim_driver.setup(_spine_sprite)
	_anim_driver.anim_completed.connect(_on_anim_completed)

	# 收集可用动画
	_collect_available_animations()

	# 初始化过渡解析器
	_transition_resolver = ExpressionTransitionResolver.new()
	_transition_resolver.debug_log = debug_log
	_transition_resolver.available_animations = _available_animations

	# 播放默认 idle
	_play_animation(&"idle_loop", true, 0)
	current_stable_anim = &"idle_loop"

	if debug_log:
		print("%s Setup complete, %d animations available" % [
			LOG_PREFIX, _available_animations.size()
		])


func get_available_animations() -> PackedStringArray:
	return _available_animations


func execute_command(command: PortraitCommand) -> void:
	## 执行立绘控制指令
	if _transition_resolver == null:
		push_error("%s Not setup yet!" % LOG_PREFIX)
		return

	# 皮肤切换
	if command.resolved_skin != &"":
		_apply_skin(command.resolved_skin)

	# 解析动画链
	_current_chain = _transition_resolver.resolve(
		current_stable_anim,
		command.target_emotion,
		command.use_talk,
		command.after_text
	)

	_pending_stable = _current_chain.stable_anim

	if debug_log:
		print("%s Executing command: emotion=%s, talk=%s" % [
			LOG_PREFIX, command.target_emotion, str(command.use_talk)
		])

	# 开始播放动画链
	if _current_chain.has_transition:
		_pending_transition_to_talk = _current_chain.talk_anim != &""
		_play_animation(_current_chain.transition_anim, false, 0)
	elif _current_chain.talk_anim != &"":
		_start_talk(_current_chain.talk_anim)
	else:
		_enter_stable(_current_chain.stable_anim)


func stop_talk() -> void:
	## 停止 talk 动画，进入稳定态
	if _is_talking:
		_is_talking = false
		_enter_stable(_pending_stable)

		if debug_log:
			print("%s Talk stopped, entering stable: %s" % [
				LOG_PREFIX, _pending_stable
			])


func force_stop() -> void:
	## 强制停止当前所有动画状态，回到稳定态
	_is_talking = false
	_pending_transition_to_talk = false
	if _pending_stable != &"":
		_enter_stable(_pending_stable)
	else:
		_enter_stable(current_stable_anim)


func _start_talk(talk_anim: StringName) -> void:
	_is_talking = true
	_play_animation(talk_anim, true, 0)

	if debug_log:
		print("%s Talk started: %s" % [LOG_PREFIX, talk_anim])


func _enter_stable(stable_anim: StringName) -> void:
	current_stable_anim = stable_anim
	_play_animation(stable_anim, true, 0)

	if debug_log:
		print("%s Entered stable: %s" % [LOG_PREFIX, stable_anim])


func _play_animation(anim_name: StringName, loop: bool, track: int) -> void:
	if _anim_driver == null:
		return
	_anim_driver.play(track, anim_name, loop, AnimDriverSpine.PlayMode.REPLACE_TRACK)


func _apply_skin(skin_name: StringName) -> void:
	if _spine_sprite == null:
		return

	# 尝试设置皮肤
	if _spine_sprite.has_method("set_skin"):
		_spine_sprite.set_skin(str(skin_name))
	elif _spine_sprite.has_method("setSkin"):
		_spine_sprite.setSkin(str(skin_name))

	if debug_log:
		print("%s Applied skin: %s" % [LOG_PREFIX, skin_name])


func _collect_available_animations() -> void:
	_available_animations = PackedStringArray()
	if _spine_sprite == null:
		return

	var skeleton_data: Object = null
	if _spine_sprite.has_method("get_skeleton"):
		var skeleton: Object = _spine_sprite.get_skeleton()
		if skeleton != null and skeleton.has_method("get_data"):
			skeleton_data = skeleton.get_data()
	elif _spine_sprite.has_method("getSkeleton"):
		var skeleton: Object = _spine_sprite.getSkeleton()
		if skeleton != null and skeleton.has_method("getData"):
			skeleton_data = skeleton.getData()

	if skeleton_data == null:
		# 兜底：使用已知测试动画名
		_available_animations = PackedStringArray([
			"idle_loop", "idle_to_talk", "talk_loop", "talk_to_idle",
			"idle_to_angry", "angry_loop", "angry_talk_loop", "angry_to_idle"
		])
		if debug_log:
			print("%s Using fallback animation list" % LOG_PREFIX)
		return

	if skeleton_data.has_method("get_animations"):
		var anims: Variant = skeleton_data.get_animations()
		if anims is Array:
			for anim: Variant in anims:
				if anim.has_method("get_name"):
					_available_animations.append(anim.get_name())
				elif "name" in anim:
					_available_animations.append(str(anim.name))

	if debug_log:
		print("%s Collected %d animations: %s" % [
			LOG_PREFIX, _available_animations.size(), str(_available_animations)
		])


func _on_anim_completed(track: int, anim_name: StringName) -> void:
	if track != 0:
		return

	if _pending_transition_to_talk and _current_chain != null:
		# 过渡动画完成，开始 talk
		_pending_transition_to_talk = false
		if _current_chain.talk_anim != &"":
			_start_talk(_current_chain.talk_anim)
		else:
			_enter_stable(_current_chain.stable_anim)
		transition_finished.emit()
		return

	if not _is_talking and anim_name == str(_pending_stable):
		# 非循环稳定态不需要额外处理
		return
