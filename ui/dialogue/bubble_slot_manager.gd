## 气泡槽位管理器
## 管理 4 个固定槽位：玩家/对方 × 当前/历史
## 处理气泡推进规则、位移动画、透明度变化和销毁
class_name BubbleSlotManager
extends Node

# ── 槽位位置（编辑器可调）──
@export_group("Slot Positions")
## 玩家当前气泡位置（左侧）
@export var player_current_pos: Vector2 = Vector2(220, 500)
## 对方当前气泡位置（右侧）
@export var other_current_pos: Vector2 = Vector2(900, 180)
## 玩家历史气泡位置
@export var player_history_pos: Vector2 = Vector2(220, 350)
## 对方历史气泡位置
@export var other_history_pos: Vector2 = Vector2(900, 50)

# ── 动画参数（编辑器可调）──
@export_group("Animation")
@export var appear_duration: float = 0.25
@export var move_to_history_duration: float = 0.35
@export var fade_out_duration: float = 0.3
@export var history_alpha: float = 0.5

# ── 气泡尺寸 ──
@export_group("Bubble Size")
@export var bubble_width: float = 380.0
@export var bubble_min_height: float = 80.0
@export var bubble_font_size: int = 18
@export var bubble_padding: int = 18

# ── 引用 ──
var _style_ctrl: BubbleStyleController

## 四个活跃气泡节点（null 表示该槽为空）
var _player_current: Control = null
var _other_current: Control = null
var _player_history: Control = null
var _other_history: Control = null

## 气泡背景纹理（由外部赋值）
var bubble_texture: Texture2D = null


func _ready() -> void:
	_style_ctrl = BubbleStyleController.new()


## 外部赋值气泡贴图
func set_bubble_texture(tex: Texture2D) -> void:
	bubble_texture = tex


## 推进气泡：role = "player" 或 "other"
## speaker_name: 显示在气泡上方的角色名（可空）
## text: 气泡文字
## flip_texture: 是否翻转气泡背景（对方使用翻转版）
func advance(role: StringName, speaker_name: String, text: String) -> void:
	var flip: bool = (role == &"other")

	# 1. 淡出并销毁已有历史气泡（同侧）
	_fade_destroy(_get_history_ref(role))
	_set_history_ref(role, null)

	# 2. 将对方历史气泡也清掉（规则C：任何时刻只保留一个历史气泡）
	var opposite_role: StringName = &"other" if role == &"player" else &"player"
	_fade_destroy(_get_history_ref(opposite_role))
	_set_history_ref(opposite_role, null)

	# 3. 将当前气泡（同侧或对侧）推入历史槽
	_push_to_history(role)
	_push_to_history(opposite_role)

	# 4. 创建新的当前气泡并淡入
	var new_bubble: Control = _create_bubble(role, speaker_name, text, flip)
	new_bubble.modulate.a = 0.0
	var target_pos: Vector2 = _get_current_pos(role)
	new_bubble.position = target_pos

	add_child(new_bubble)
	_set_current_ref(role, new_bubble)

	var tw: Tween = create_tween()
	tw.tween_property(new_bubble, "modulate:a", 1.0, appear_duration)


## 清除所有气泡（对话结束时调用）
func clear_all() -> void:
	for bubble: Control in [_player_current, _other_current, _player_history, _other_history]:
		if bubble != null and is_instance_valid(bubble):
			bubble.queue_free()
	_player_current = null
	_other_current = null
	_player_history = null
	_other_history = null


## ── 内部方法 ──

func _push_to_history(role: StringName) -> void:
	var cur: Control = _get_current_ref(role)
	if cur == null or not is_instance_valid(cur):
		_set_current_ref(role, null)
		return

	var history_pos: Vector2 = _get_history_pos(role)
	_set_history_ref(role, cur)
	_set_current_ref(role, null)

	var tw: Tween = create_tween()
	tw.set_parallel(true)
	tw.tween_property(cur, "position", history_pos, move_to_history_duration)
	tw.tween_property(cur, "modulate:a", history_alpha, move_to_history_duration)


func _fade_destroy(bubble: Control) -> void:
	if bubble == null or not is_instance_valid(bubble):
		return
	var tw: Tween = create_tween()
	tw.tween_property(bubble, "modulate:a", 0.0, fade_out_duration)
	tw.tween_callback(bubble.queue_free)


func _create_bubble(role: StringName, speaker_name: String, text: String, flip: bool) -> Control:
	var root: Control = Control.new()
	root.custom_minimum_size = Vector2(bubble_width, bubble_min_height)

	# 背景（TextureRect，可翻转）
	if bubble_texture != null:
		var bg: TextureRect = TextureRect.new()
		bg.texture = bubble_texture
		bg.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		bg.stretch_mode = TextureRect.STRETCH_SCALE
		bg.flip_h = flip
		bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		bg.modulate = _style_ctrl.get_bubble_modulate(role, false)
		root.add_child(bg)

	# 内容容器
	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", bubble_padding)
	margin.add_theme_constant_override("margin_right", bubble_padding)
	margin.add_theme_constant_override("margin_top", bubble_padding)
	margin.add_theme_constant_override("margin_bottom", bubble_padding)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)

	# 角色名
	if speaker_name != "":
		var name_lbl: Label = Label.new()
		name_lbl.text = speaker_name
		name_lbl.add_theme_font_size_override("font_size", bubble_font_size - 2)
		name_lbl.add_theme_color_override("font_color", Color(1.0, 0.8, 0.4))
		vbox.add_child(name_lbl)

	# 对话文字
	var txt_lbl: Label = Label.new()
	txt_lbl.text = text
	txt_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	txt_lbl.add_theme_font_size_override("font_size", bubble_font_size)
	txt_lbl.add_theme_color_override("font_color", _style_ctrl.get_text_color(role))
	txt_lbl.custom_minimum_size = Vector2(bubble_width - bubble_padding * 2, 0)
	vbox.add_child(txt_lbl)

	margin.add_child(vbox)
	root.add_child(margin)

	return root


## ── 槽位访问辅助 ──

func _get_current_pos(role: StringName) -> Vector2:
	if role == &"player":
		return player_current_pos
	return other_current_pos


func _get_history_pos(role: StringName) -> Vector2:
	if role == &"player":
		return player_history_pos
	return other_history_pos


func _get_current_ref(role: StringName) -> Control:
	if role == &"player":
		return _player_current
	return _other_current


func _set_current_ref(role: StringName, node: Control) -> void:
	if role == &"player":
		_player_current = node
	else:
		_other_current = node


func _get_history_ref(role: StringName) -> Control:
	if role == &"player":
		return _player_history
	return _other_history


func _set_history_ref(role: StringName, node: Control) -> void:
	if role == &"player":
		_player_history = node
	else:
		_other_history = node
