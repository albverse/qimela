class_name ItemTooltipUI
extends PanelContainer

## 道具说明浮窗
## 高亮停留 >= 3 秒后弹出，移走后缩小消失

var _name_label: Label = null
var _desc_label: RichTextLabel = null
var _category_label: Label = null
var _appear_tween: Tween = null

const TOOLTIP_WIDTH: float = 200.0


func _ready() -> void:
	custom_minimum_size = Vector2(TOOLTIP_WIDTH, 0)
	visible = false
	scale = Vector2.ZERO
	pivot_offset = Vector2(TOOLTIP_WIDTH * 0.5, 40.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	# 背景样式
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.06, 0.14, 0.92)
	style.border_color = Color(0.6, 0.5, 0.9, 0.8)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(8)
	add_theme_stylebox_override("panel", style)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(vbox)

	# 道具名
	_name_label = Label.new()
	_name_label.add_theme_font_size_override("font_size", 14)
	_name_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5))
	vbox.add_child(_name_label)

	# 类别
	_category_label = Label.new()
	_category_label.add_theme_font_size_override("font_size", 10)
	_category_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
	vbox.add_child(_category_label)

	# 说明
	_desc_label = RichTextLabel.new()
	_desc_label.bbcode_enabled = false
	_desc_label.fit_content = true
	_desc_label.scroll_active = false
	_desc_label.custom_minimum_size = Vector2(TOOLTIP_WIDTH - 16.0, 0)
	_desc_label.add_theme_font_size_override("normal_font_size", 11)
	_desc_label.add_theme_color_override("default_color", Color(0.85, 0.85, 0.9))
	vbox.add_child(_desc_label)


func show_for_item(item: ItemData, count: int, slot_global_pos: Vector2) -> void:
	if item == null:
		hide_tooltip()
		return

	_name_label.text = item.display_name
	_category_label.text = _category_text(item.category)
	_desc_label.text = item.desc_short
	if count > 1:
		_desc_label.text += "\n数量: %d" % count

	# 定位到格子上方
	visible = true
	global_position = slot_global_pos + Vector2(-TOOLTIP_WIDTH * 0.5 + 28.0, -100.0)

	# 弹出动画
	if _appear_tween != null and _appear_tween.is_valid():
		_appear_tween.kill()
	_appear_tween = create_tween()
	_appear_tween.tween_property(self, "scale", Vector2.ONE, 0.15).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)


func hide_tooltip() -> void:
	if not visible:
		return
	if _appear_tween != null and _appear_tween.is_valid():
		_appear_tween.kill()
	_appear_tween = create_tween()
	_appear_tween.tween_property(self, "scale", Vector2.ZERO, 0.12).set_ease(Tween.EASE_IN)
	_appear_tween.tween_callback(func() -> void: visible = false)


func _category_text(cat: int) -> String:
	match cat:
		ItemData.ItemCategory.HEAL:
			return "[回复]"
		ItemData.ItemCategory.HEALING_SPRITE:
			return "[治愈精灵]"
		ItemData.ItemCategory.PUZZLE_PROP:
			return "[解密道具]"
		ItemData.ItemCategory.ATTACK_MAGIC:
			return "[攻击魔法]"
		ItemData.ItemCategory.CHIMERA_CAPSULE:
			return "[奇美拉胶囊]"
		ItemData.ItemCategory.KEY_ITEM:
			return "[关键道具]"
	return "[道具]"
