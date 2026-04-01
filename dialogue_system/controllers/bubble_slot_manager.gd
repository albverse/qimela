extends Node
class_name BubbleSlotManager

## 气泡槽位管理器
## 职责：管理四个固定槽位的气泡生命周期、位置、透明度、历史推进
## 不读取 Dialogue 文件，不控制 Spine 动画

const LOG_PREFIX: String = "[BubbleSlot]"

signal bubble_typing_finished()

@export var debug_log: bool = false

## 槽位位置（编辑器可调）
@export var player_current_slot_position: Vector2 = Vector2(180, 200)
@export var other_current_slot_position: Vector2 = Vector2(780, 200)
@export var player_history_slot_position: Vector2 = Vector2(180, 60)
@export var other_history_slot_position: Vector2 = Vector2(780, 60)

## 动画参数（编辑器可调）
@export var bubble_enter_duration: float = 0.3
@export var bubble_to_history_duration: float = 0.4
@export var history_fadeout_duration: float = 0.3
@export var history_opacity: float = 0.5

## 历史文本缩略参数
@export var history_shrink_threshold: int = 100
@export var history_preview_char_count: int = 20
@export var history_preview_suffix: String = "……"

## 打字机速度
@export var typewriter_speed: float = 30.0

## 气泡场景引用
var bubble_scene: PackedScene = null

## 样式控制器引用
var style_controller: BubbleStyleController = null

## 槽位容器节点
var _slots_container: Control = null

## 当前活跃气泡
var _player_current_bubble: DialogueBubble = null
var _other_current_bubble: DialogueBubble = null
var _player_history_bubble: DialogueBubble = null
var _other_history_bubble: DialogueBubble = null

## 当前气泡的完整文本（用于历史缩略）
var _player_current_full_text: String = ""
var _other_current_full_text: String = ""


func setup(container: Control, scene: PackedScene, style_ctrl: BubbleStyleController) -> void:
	_slots_container = container
	bubble_scene = scene
	style_controller = style_ctrl

	if debug_log:
		print("%s Setup complete" % LOG_PREFIX)


func show_bubble(payload: BubblePayload) -> void:
	## 显示新的当前气泡，处理历史推进
	var role: StringName = payload.speaker_role

	if role == &"player":
		_advance_player_bubble(payload)
	else:
		_advance_other_bubble(payload)


func skip_current_typing() -> void:
	## 跳过当前气泡打字机
	if _player_current_bubble != null and _player_current_bubble.is_typing():
		_player_current_bubble.skip_typing()
	if _other_current_bubble != null and _other_current_bubble.is_typing():
		_other_current_bubble.skip_typing()


func is_any_typing() -> bool:
	if _player_current_bubble != null and _player_current_bubble.is_typing():
		return true
	if _other_current_bubble != null and _other_current_bubble.is_typing():
		return true
	return false


func clear_all() -> void:
	## 清除所有气泡
	_destroy_bubble(_player_current_bubble)
	_destroy_bubble(_other_current_bubble)
	_destroy_bubble(_player_history_bubble)
	_destroy_bubble(_other_history_bubble)
	_player_current_bubble = null
	_other_current_bubble = null
	_player_history_bubble = null
	_other_history_bubble = null


## ── 内部：玩家气泡推进 ──

func _advance_player_bubble(payload: BubblePayload) -> void:
	# 1. 旧历史气泡淡出销毁
	_fadeout_and_destroy(_player_history_bubble)
	_player_history_bubble = null

	# 2. 当前气泡 → 历史
	if _player_current_bubble != null:
		_player_history_bubble = _player_current_bubble
		_move_to_history(
			_player_history_bubble,
			player_history_slot_position,
			&"player",
			_player_current_full_text
		)

	# 3. 同时处理对方的历史气泡（规则C：任何时刻最多只有一个历史气泡）
	# 如果对方有历史气泡，淡出
	_fadeout_and_destroy(_other_history_bubble)
	_other_history_bubble = null

	# 4. 创建新的当前气泡
	_player_current_full_text = payload.full_text
	_player_current_bubble = _create_bubble(
		payload,
		player_current_slot_position,
		&"player"
	)

	if debug_log:
		print("%s Player bubble advanced, text: %s" % [
			LOG_PREFIX, payload.full_text.left(30)
		])


func _advance_other_bubble(payload: BubblePayload) -> void:
	# 1. 旧历史气泡淡出销毁
	_fadeout_and_destroy(_other_history_bubble)
	_other_history_bubble = null

	# 2. 当前气泡 → 历史
	if _other_current_bubble != null:
		_other_history_bubble = _other_current_bubble
		_move_to_history(
			_other_history_bubble,
			other_history_slot_position,
			&"other",
			_other_current_full_text
		)

	# 3. 清理玩家历史
	_fadeout_and_destroy(_player_history_bubble)
	_player_history_bubble = null

	# 4. 创建新的当前气泡
	_other_current_full_text = payload.full_text
	_other_current_bubble = _create_bubble(
		payload,
		other_current_slot_position,
		&"other"
	)

	if debug_log:
		print("%s Other bubble advanced, text: %s" % [
			LOG_PREFIX, payload.full_text.left(30)
		])


## ── 内部：气泡创建与动画 ──

func _create_bubble(
	payload: BubblePayload,
	slot_position: Vector2,
	role: StringName
) -> DialogueBubble:
	if bubble_scene == null:
		push_error("%s bubble_scene is null!" % LOG_PREFIX)
		return null

	var bubble: DialogueBubble = bubble_scene.instantiate() as DialogueBubble
	_slots_container.add_child(bubble)
	bubble.position = slot_position

	# 应用样式
	if style_controller != null:
		var texture: Texture2D = style_controller.get_bubble_texture(role, payload.bubble_style_id)
		if texture != null:
			bubble.bubble_texture = texture

	# 入场动画
	bubble.modulate.a = 0.0
	bubble.scale = Vector2(0.9, 0.9)
	var tw: Tween = bubble.create_tween()
	tw.set_parallel(true)
	tw.tween_property(bubble, "modulate:a", 1.0, bubble_enter_duration)
	tw.tween_property(bubble, "scale", Vector2(1.0, 1.0), bubble_enter_duration).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)

	# 显示文本（打字机效果）
	bubble.show_with_typewriter(payload, typewriter_speed)
	bubble.typing_finished.connect(_on_bubble_typing_finished, CONNECT_ONE_SHOT)

	return bubble


func _move_to_history(
	bubble: DialogueBubble,
	history_position: Vector2,
	role: StringName,
	full_text: String
) -> void:
	if bubble == null:
		return

	# 断开旧的打字完成信号
	if bubble.typing_finished.is_connected(_on_bubble_typing_finished):
		bubble.typing_finished.disconnect(_on_bubble_typing_finished)

	# 如果还在打字，直接完成
	if bubble.is_typing():
		bubble.skip_typing()

	# 历史文本缩略
	var preview_text: String = full_text
	if full_text.length() > history_shrink_threshold:
		preview_text = BubblePayload.build_history_preview_text(
			full_text, history_preview_char_count, history_preview_suffix
		)
	bubble.convert_to_history(preview_text)

	# 应用历史样式
	if style_controller != null:
		style_controller.apply_history_style(bubble, role)

	# 移动动画
	var tw: Tween = bubble.create_tween()
	tw.set_parallel(true)
	tw.tween_property(bubble, "position", history_position, bubble_to_history_duration).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(bubble, "modulate:a", history_opacity, bubble_to_history_duration)


func _fadeout_and_destroy(bubble: DialogueBubble) -> void:
	if bubble == null:
		return

	# 断开信号
	if bubble.typing_finished.is_connected(_on_bubble_typing_finished):
		bubble.typing_finished.disconnect(_on_bubble_typing_finished)

	var tw: Tween = bubble.create_tween()
	tw.tween_property(bubble, "modulate:a", 0.0, history_fadeout_duration)
	tw.finished.connect(bubble.queue_free)


func _destroy_bubble(bubble: DialogueBubble) -> void:
	if bubble != null and is_instance_valid(bubble):
		bubble.queue_free()


func _on_bubble_typing_finished() -> void:
	bubble_typing_finished.emit()

	if debug_log:
		print("%s Typing finished" % LOG_PREFIX)
