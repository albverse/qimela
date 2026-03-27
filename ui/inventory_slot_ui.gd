class_name InventorySlotUI
extends Control

## 单个背包格子 UI
## 负责：图标显示、数量角标、冷却遮罩、高亮/抖动动画

@export var slot_index: int = 0

# ── 子节点引用 ──
var _bg: ColorRect = null
var _icon: TextureRect = null
var _count_label: Label = null
var _cooldown_overlay: ColorRect = null
var _highlight_rect: ColorRect = null

# ── 视觉状态 ──
enum SlotVisual { EMPTY, NORMAL, HIGHLIGHT, COOLDOWN, DISABLED, PLUS_SLOT }
var _visual_state: int = SlotVisual.EMPTY

# ── 数据缓存 ──
var _item_data: ItemData = null
var _item_count: int = 0
var _cooldown_ratio: float = 0.0
var _is_plus_slot: bool = false
var _plus_label: Label = null


func _ready() -> void:
	custom_minimum_size = Vector2(56, 56)

	# 背景
	_bg = ColorRect.new()
	_bg.color = Color(0.12, 0.12, 0.16, 0.7)
	_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_bg)

	# 图标
	_icon = TextureRect.new()
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_icon.offset_left = 4.0
	_icon.offset_top = 4.0
	_icon.offset_right = -4.0
	_icon.offset_bottom = -12.0
	add_child(_icon)

	# 冷却遮罩
	_cooldown_overlay = ColorRect.new()
	_cooldown_overlay.color = Color(0.0, 0.0, 0.0, 0.5)
	_cooldown_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_cooldown_overlay.visible = false
	add_child(_cooldown_overlay)

	# 数量角标
	_count_label = Label.new()
	_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_count_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_count_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_count_label.offset_right = -3.0
	_count_label.offset_bottom = -1.0
	_count_label.add_theme_font_size_override("font_size", 12)
	_count_label.add_theme_color_override("font_color", Color.WHITE)
	_count_label.text = ""
	add_child(_count_label)

	# 高亮框
	_highlight_rect = ColorRect.new()
	_highlight_rect.color = Color(1.0, 0.85, 0.3, 0.35)
	_highlight_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_highlight_rect.visible = false
	_highlight_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_highlight_rect)

	_update_visual()


func set_as_plus_slot() -> void:
	## 将此格设为 "+" 功能键（OtherItems 入口）
	_is_plus_slot = true
	_item_data = null
	_item_count = 0
	_icon.texture = null
	_count_label.text = ""
	_cooldown_overlay.visible = false
	# 创建 "+" 标签
	if _plus_label == null:
		_plus_label = Label.new()
		_plus_label.text = "+"
		_plus_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_plus_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_plus_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_plus_label.add_theme_font_size_override("font_size", 24)
		_plus_label.add_theme_color_override("font_color", Color(0.7, 0.6, 0.9, 0.8))
		_plus_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_plus_label)
	_plus_label.visible = true
	_bg.color = Color(0.15, 0.13, 0.22, 0.6)
	_visual_state = SlotVisual.PLUS_SLOT


func set_slot_data(item: ItemData, count: int, cooldown_ratio: float) -> void:
	_item_data = item
	_item_count = count
	_cooldown_ratio = cooldown_ratio
	_update_visual()


func clear_slot() -> void:
	_item_data = null
	_item_count = 0
	_cooldown_ratio = 0.0
	_update_visual()


func set_highlighted(highlighted: bool) -> void:
	_highlight_rect.visible = highlighted
	if highlighted:
		_visual_state = SlotVisual.HIGHLIGHT
		# 轻微放大效果
		var tw: Tween = create_tween()
		tw.tween_property(self, "scale", Vector2(1.06, 1.06), 0.08).set_ease(Tween.EASE_OUT)
	else:
		# 恢复正常大小
		var tw: Tween = create_tween()
		tw.tween_property(self, "scale", Vector2.ONE, 0.08).set_ease(Tween.EASE_OUT)
		if _item_data != null:
			_visual_state = SlotVisual.NORMAL
		else:
			_visual_state = SlotVisual.EMPTY


func play_use_flash() -> void:
	## 使用成功闪白反馈
	var tw: Tween = create_tween()
	_bg.color = Color(1.0, 1.0, 1.0, 0.8)
	tw.tween_property(_bg, "color", Color(0.12, 0.12, 0.16, 0.7), 0.3)


func play_fail_shake() -> void:
	## 使用失败抖动反馈
	var tw: Tween = create_tween()
	var orig_pos: Vector2 = position
	tw.tween_property(self, "position", orig_pos + Vector2(4, 0), 0.04)
	tw.tween_property(self, "position", orig_pos + Vector2(-4, 0), 0.04)
	tw.tween_property(self, "position", orig_pos + Vector2(2, 0), 0.04)
	tw.tween_property(self, "position", orig_pos, 0.04)
	# 红闪
	_bg.color = Color(0.8, 0.15, 0.15, 0.7)
	var tw2: Tween = create_tween()
	tw2.tween_property(_bg, "color", Color(0.12, 0.12, 0.16, 0.7), 0.3)


func _update_visual() -> void:
	if _icon == null:
		return

	# "+" 功能格保持自身外观
	if _is_plus_slot:
		return

	# 隐藏 "+" 标签（非功能格）
	if _plus_label != null:
		_plus_label.visible = false

	if _item_data == null:
		_icon.texture = null
		_count_label.text = ""
		_cooldown_overlay.visible = false
		_bg.color = Color(0.08, 0.08, 0.1, 0.5)
		_visual_state = SlotVisual.EMPTY
		return

	_icon.texture = _item_data.inventory_icon
	_bg.color = Color(0.12, 0.12, 0.16, 0.7)

	# 数量角标（可堆叠物品始终显示数量）
	if _item_data.max_stack > 1:
		_count_label.text = "x%d" % _item_count
	else:
		_count_label.text = ""

	# 冷却遮罩
	if _cooldown_ratio > 0.0:
		_cooldown_overlay.visible = true
		_cooldown_overlay.color.a = 0.5 * _cooldown_ratio
		_visual_state = SlotVisual.COOLDOWN
	else:
		_cooldown_overlay.visible = false
		_visual_state = SlotVisual.NORMAL
