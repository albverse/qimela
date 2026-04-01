@tool
extends Control
class_name DialogueBubble

## 单个对话气泡组件
## 包含背景纹理 + 文本标签
## 作为独立场景，方便美术调控

const LOG_PREFIX: String = "[DialogueBubble]"

signal typing_finished()

@export var bubble_texture: Texture2D:
	set(value):
		bubble_texture = value
		if is_node_ready():
			_update_bubble_texture()

@export var text_margin: Vector4 = Vector4(40, 30, 40, 30):  ## left, top, right, bottom
	set(value):
		text_margin = value
		if is_node_ready():
			_update_text_margins()

@export var min_bubble_size: Vector2 = Vector2(200, 80)
@export var max_bubble_width: float = 500.0

## 内部节点引用
var _bubble_bg: NinePatchRect = null
var _dialogue_label: RichTextLabel = null
var _payload: BubblePayload = null
var _typing_tween: Tween = null
var _typing_completed: bool = false


func _ready() -> void:
	_bubble_bg = $BubbleBG as NinePatchRect
	_dialogue_label = $BubbleBG/MarginContainer/DialogueLabel as RichTextLabel

	_update_bubble_texture()
	_update_text_margins()


func set_payload(payload: BubblePayload) -> void:
	_payload = payload
	if _dialogue_label == null:
		return

	var display_text: String = payload.full_text
	if payload.is_history:
		display_text = payload.history_preview_text

	_dialogue_label.text = ""
	_dialogue_label.text = display_text


func show_with_typewriter(payload: BubblePayload, chars_per_second: float = 30.0) -> void:
	_payload = payload
	if _dialogue_label == null:
		return

	_typing_completed = false
	_dialogue_label.text = payload.full_text
	_dialogue_label.visible_characters = 0

	# 使用 tween 实现打字机效果
	var total_chars: int = payload.full_text.length()
	if total_chars <= 0:
		typing_finished.emit()
		return

	var duration: float = float(total_chars) / chars_per_second
	if _typing_tween != null and _typing_tween.is_valid():
		_typing_tween.kill()
	_typing_tween = create_tween()
	_typing_tween.tween_property(_dialogue_label, "visible_characters", total_chars, duration)
	_typing_tween.finished.connect(_on_typing_complete)


func skip_typing() -> void:
	## 跳过打字机，直接显示全部文本
	if _dialogue_label == null:
		return
	# 停止所有活跃 tween
	if _typing_tween != null and _typing_tween.is_valid():
		_typing_tween.kill()
		_typing_tween = null
	# 直接设置为全显示
	_dialogue_label.visible_characters = -1
	_on_typing_complete()


func is_typing() -> bool:
	if _dialogue_label == null:
		return false
	var total: int = _dialogue_label.text.length()
	return _dialogue_label.visible_characters >= 0 and _dialogue_label.visible_characters < total


func convert_to_history(preview_text: String) -> void:
	## 转为历史态：替换文本为缩略版
	if _dialogue_label == null:
		return
	_dialogue_label.visible_characters = -1
	_dialogue_label.text = preview_text
	if _payload != null:
		_payload.is_history = true


func _on_typing_complete() -> void:
	if _typing_completed:
		return
	_typing_completed = true
	if _dialogue_label != null:
		_dialogue_label.visible_characters = -1
	typing_finished.emit()


func _update_bubble_texture() -> void:
	if _bubble_bg != null and bubble_texture != null:
		_bubble_bg.texture = bubble_texture


func _update_text_margins() -> void:
	var margin_container: MarginContainer = null
	if _bubble_bg != null:
		margin_container = _bubble_bg.get_node_or_null("MarginContainer") as MarginContainer
	if margin_container == null:
		return
	margin_container.add_theme_constant_override("margin_left", int(text_margin.x))
	margin_container.add_theme_constant_override("margin_top", int(text_margin.y))
	margin_container.add_theme_constant_override("margin_right", int(text_margin.z))
	margin_container.add_theme_constant_override("margin_bottom", int(text_margin.w))
