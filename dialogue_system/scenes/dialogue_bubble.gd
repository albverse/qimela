@tool
extends Control
class_name DialogueBubble

## 对话气泡组件（独立场景）
##
## 【美术使用说明】
## 本场景作为独立 .tscn，美术可自由修改：
## 1. BubbleBG：气泡背景节点，类型为 NinePatchRect
##    - 支持赋予 ShaderMaterial 制作动态效果
##    - 支持替换 texture 改变气泡样式
##    - 支持通过 AnimationPlayer 制作帧动画气泡
## 2. MarginContainer：控制文字与气泡边缘的间距
## 3. DialogueLabel：RichTextLabel，支持 BBCode 富文本
## 4. NameLabel：角色名标签
## 5. AnimationPlayer：可添加气泡动效（入场、循环呼吸等）

const LOG_PREFIX: String = "[DialogueBubble]"

signal typing_finished()

## ── 美术可调参数 ──
@export_group("Bubble Style")
## 气泡背景纹理（运行时可动态替换）
@export var bubble_texture: Texture2D:
	set(value):
		bubble_texture = value
		if is_node_ready():
			_update_bubble_texture()

## 气泡背景材质（可赋予 ShaderMaterial 实现动效）
@export var bubble_material: Material:
	set(value):
		bubble_material = value
		if is_node_ready():
			_update_bubble_material()

@export_group("Text Layout")
## 文字边距：左、上、右、下
@export var text_margin: Vector4 = Vector4(50, 25, 50, 45):
	set(value):
		text_margin = value
		if is_node_ready():
			_update_text_margins()

## ── 抖动动效参数 ──
@export_group("Shake Effect")
## 抖动强度（像素）
@export var shake_intensity: float = 6.0
## 抖动持续时间
@export var shake_duration: float = 0.4
## 抖动频率（次/秒）
@export var shake_frequency: float = 30.0

## 内部节点引用
var _bubble_bg: Node = null  ## NinePatchRect
var _dialogue_label: RichTextLabel = null
var _name_label: Label = null
var _anim_player: AnimationPlayer = null
var _payload: BubblePayload = null
var _typing_tween: Tween = null
var _typing_completed: bool = false
var _shake_tween: Tween = null
var _original_position: Vector2 = Vector2.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_bubble_bg = $BubbleBG
	_dialogue_label = $BubbleBG/MarginContainer/DialogueLabel as RichTextLabel
	_name_label = get_node_or_null("NameLabel") as Label
	_anim_player = get_node_or_null("AnimationPlayer") as AnimationPlayer

	_update_bubble_texture()
	_update_bubble_material()
	_update_text_margins()
	_original_position = position


func set_payload(payload: BubblePayload) -> void:
	_payload = payload
	if _dialogue_label == null:
		return

	var display_text: String = payload.full_text
	if payload.is_history:
		display_text = payload.history_preview_text

	_dialogue_label.text = display_text


func set_speaker_name(speaker_name: String) -> void:
	if _name_label != null:
		_name_label.text = speaker_name
		_name_label.visible = speaker_name.length() > 0


func show_with_typewriter(payload: BubblePayload, chars_per_second: float = 30.0) -> void:
	_payload = payload
	if _dialogue_label == null:
		return

	_typing_completed = false
	_dialogue_label.text = payload.full_text
	_dialogue_label.visible_characters = 0

	var total_chars: int = payload.full_text.length()
	if total_chars <= 0:
		_on_typing_complete()
		return

	var duration: float = float(total_chars) / chars_per_second
	if _typing_tween != null and _typing_tween.is_valid():
		_typing_tween.kill()
	_typing_tween = create_tween()
	_typing_tween.tween_property(_dialogue_label, "visible_characters", total_chars, duration)
	_typing_tween.finished.connect(_on_typing_complete)


func skip_typing() -> void:
	if _dialogue_label == null:
		return
	if _typing_tween != null and _typing_tween.is_valid():
		_typing_tween.kill()
		_typing_tween = null
	_dialogue_label.visible_characters = -1
	_on_typing_complete()


func is_typing() -> bool:
	if _dialogue_label == null:
		return false
	var total: int = _dialogue_label.text.length()
	return _dialogue_label.visible_characters >= 0 and _dialogue_label.visible_characters < total


func convert_to_history(preview_text: String) -> void:
	if _dialogue_label == null:
		return
	_dialogue_label.visible_characters = -1
	_dialogue_label.text = preview_text
	if _payload != null:
		_payload.is_history = true


## ── 动效 API ──

func play_shake() -> void:
	## 播放抖动动效（表现角色惊讶/震惊）
	if _shake_tween != null and _shake_tween.is_valid():
		_shake_tween.kill()

	_original_position = position
	var elapsed: float = 0.0
	var step: float = 1.0 / shake_frequency
	var steps: int = int(shake_duration * shake_frequency)

	_shake_tween = create_tween()
	for i: int in range(steps):
		var decay: float = 1.0 - (float(i) / float(steps))
		var offset_x: float = randf_range(-shake_intensity, shake_intensity) * decay
		var offset_y: float = randf_range(-shake_intensity, shake_intensity) * decay
		_shake_tween.tween_property(
			self, "position",
			_original_position + Vector2(offset_x, offset_y),
			step
		)
		elapsed += step
	_shake_tween.tween_property(self, "position", _original_position, step)


func play_custom_animation(anim_name: String) -> void:
	## 播放 AnimationPlayer 中预制的自定义动画
	if _anim_player != null and _anim_player.has_animation(anim_name):
		_anim_player.play(anim_name)


func set_bubble_texture_runtime(texture: Texture2D) -> void:
	## 运行时动态替换气泡纹理
	bubble_texture = texture


func set_bubble_material_runtime(mat: Material) -> void:
	## 运行时动态替换气泡材质/shader
	bubble_material = mat


## ── 内部 ──

func _on_typing_complete() -> void:
	if _typing_completed:
		return
	_typing_completed = true
	if _dialogue_label != null:
		_dialogue_label.visible_characters = -1
	typing_finished.emit()


func _update_bubble_texture() -> void:
	if _bubble_bg == null or bubble_texture == null:
		return
	if _bubble_bg is NinePatchRect:
		(_bubble_bg as NinePatchRect).texture = bubble_texture
	elif _bubble_bg is TextureRect:
		(_bubble_bg as TextureRect).texture = bubble_texture


func _update_bubble_material() -> void:
	if _bubble_bg == null:
		return
	if _bubble_bg is CanvasItem:
		(_bubble_bg as CanvasItem).material = bubble_material


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
