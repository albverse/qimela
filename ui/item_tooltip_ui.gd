class_name ItemTooltipUI
extends PanelContainer

## 道具说明浮窗
## 高亮停留 >= 3 秒后弹出，进入锁定显示状态
## 锁定后切换物品仅更新内容（不重播动画），重排/使用/关闭时才重置

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
	## 首次弹出（播放动画）
	if item == null:
		hide_tooltip()
		return

	_set_content(item, count)

	# 定位到格子上方
	visible = true
	global_position = slot_global_pos + Vector2(-TOOLTIP_WIDTH * 0.5 + 28.0, -100.0)
	_clamp_to_screen()

	# 弹出动画
	if _appear_tween != null and _appear_tween.is_valid():
		_appear_tween.kill()
	_appear_tween = create_tween()
	_appear_tween.tween_property(self, "scale", Vector2.ONE, 0.15).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)


func update_content(item: ItemData, count: int, slot_global_pos: Vector2) -> void:
	## 锁定显示状态下切换物品：仅更新文本和位置，不重播动画
	if item == null:
		hide_tooltip()
		return

	_set_content(item, count)
	global_position = slot_global_pos + Vector2(-TOOLTIP_WIDTH * 0.5 + 28.0, -100.0)
	_clamp_to_screen()


func hide_tooltip() -> void:
	if not visible:
		return
	if _appear_tween != null and _appear_tween.is_valid():
		_appear_tween.kill()
	_appear_tween = create_tween()
	_appear_tween.tween_property(self, "scale", Vector2.ZERO, 0.12).set_ease(Tween.EASE_IN)
	_appear_tween.tween_callback(func() -> void: visible = false)


func _set_content(item: ItemData, count: int) -> void:
	_name_label.text = item.display_name
	_category_label.text = _category_text(item)
	_desc_label.text = item.desc_short
	if count > 1:
		_desc_label.text += "\n数量: %d" % count


func _category_text(item: ItemData) -> String:
	## 根据 sub_category + use_type 生成分类标签
	match item.sub_category:
		ItemData.SubCategory.KEY_ITEM:
			return "[关键道具]"
		ItemData.SubCategory.MATERIAL:
			return "[素材]"
		ItemData.SubCategory.CONSUMABLE:
			# 消耗品细分显示
			match item.use_type:
				ItemData.UseType.HEAL:
					return "[回复]"
				ItemData.UseType.SUMMON_SPRITE:
					return "[治愈精灵]"
				ItemData.UseType.ATTACK_MAGIC:
					return "[攻击魔法]"
				ItemData.UseType.DEPLOY_PROP:
					return "[解密道具]"
				ItemData.UseType.SUMMON_CHIMERA:
					return "[奇美拉胶囊]"
			return "[消耗品]"
	return "[道具]"


func _clamp_to_screen() -> void:
	## 防止 Tooltip 超出屏幕边界
	var vp_size: Vector2 = get_viewport_rect().size
	if global_position.x < 8.0:
		global_position.x = 8.0
	if global_position.x + TOOLTIP_WIDTH > vp_size.x - 8.0:
		global_position.x = vp_size.x - TOOLTIP_WIDTH - 8.0
	if global_position.y < 8.0:
		global_position.y = 8.0
