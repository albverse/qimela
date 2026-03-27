class_name OtherItemsPanelUI
extends PanelContainer

## OtherItems 面板（一般掉落物查看与扔出）
## 从主背包 "+" 格进入，显示 MATERIAL 物品列表
## 支持上下导航、选中后按 E 弹出扔出确认

const ROW_HEIGHT: float = 40.0
const PANEL_WIDTH: float = 280.0
const MAX_VISIBLE_ROWS: int = 8

var _vbox: VBoxContainer = null
var _title_label: Label = null
var _scroll: ScrollContainer = null
var _items_vbox: VBoxContainer = null
var _rows: Array = []  # Array[Control] 当前显示的行
var _empty_label: Label = null

var _inventory: PlayerInventory = null
var _selected_index: int = 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(PANEL_WIDTH, 0)

	# 面板样式
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.05, 0.12, 0.92)
	style.border_color = Color(0.5, 0.4, 0.8, 0.6)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(10)
	add_theme_stylebox_override("panel", style)

	# 居中偏上
	set_anchors_preset(Control.PRESET_CENTER)
	offset_left = -PANEL_WIDTH * 0.5
	offset_right = PANEL_WIDTH * 0.5
	offset_top = -180.0
	offset_bottom = 100.0

	_vbox = VBoxContainer.new()
	_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_vbox)

	# 标题
	_title_label = Label.new()
	_title_label.text = "其他物品"
	_title_label.add_theme_font_size_override("font_size", 14)
	_title_label.add_theme_color_override("font_color", Color(0.8, 0.75, 0.95))
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_vbox.add_child(_title_label)

	# 分隔
	var sep: HSeparator = HSeparator.new()
	_vbox.add_child(sep)

	# 滚动容器
	_scroll = ScrollContainer.new()
	_scroll.custom_minimum_size = Vector2(0, MAX_VISIBLE_ROWS * ROW_HEIGHT)
	_scroll.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vbox.add_child(_scroll)

	_items_vbox = VBoxContainer.new()
	_items_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scroll.add_child(_items_vbox)

	# 空列表提示
	_empty_label = Label.new()
	_empty_label.text = "暂无物品"
	_empty_label.add_theme_font_size_override("font_size", 11)
	_empty_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.6))
	_empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_label.visible = false
	_items_vbox.add_child(_empty_label)


func set_inventory(inv: PlayerInventory) -> void:
	_inventory = inv


func refresh_and_show() -> void:
	## 刷新列表并显示面板
	_rebuild_list()
	visible = true


func get_selected_index() -> int:
	return _selected_index


func move_selection(dir: int) -> void:
	## dir: -1 = 上, +1 = 下
	if _rows.is_empty():
		return
	var old_idx: int = _selected_index
	_selected_index += dir
	if _selected_index < 0:
		_selected_index = _rows.size() - 1
	elif _selected_index >= _rows.size():
		_selected_index = 0
	if old_idx != _selected_index:
		_update_highlight()


func _rebuild_list() -> void:
	# 清理旧行
	for row: Control in _rows:
		row.queue_free()
	_rows.clear()

	if _inventory == null:
		_empty_label.visible = true
		return

	var snapshot: Array = _inventory.get_other_items_snapshot()
	if snapshot.is_empty():
		_empty_label.visible = true
		return

	_empty_label.visible = false
	_selected_index = _inventory.get_other_selected()

	for i in range(snapshot.size()):
		var entry: Dictionary = snapshot[i] as Dictionary
		var item: ItemData = entry["item"] as ItemData
		var count: int = entry["count"] as int
		var row: HBoxContainer = _create_row(item, count, i)
		_items_vbox.add_child(row)
		_rows.append(row)

	_update_highlight()


func _create_row(item: ItemData, count: int, _index: int) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, ROW_HEIGHT)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 6)

	# 背景
	var bg: ColorRect = ColorRect.new()
	bg.color = Color(0.1, 0.1, 0.14, 0.5)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(bg)

	# 图标
	var icon_rect: TextureRect = TextureRect.new()
	icon_rect.custom_minimum_size = Vector2(32, 32)
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	if item.inventory_icon != null:
		icon_rect.texture = item.inventory_icon
	icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon_rect)

	# 名称
	var name_label: Label = Label.new()
	name_label.text = item.display_name
	name_label.add_theme_font_size_override("font_size", 12)
	name_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.9))
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(name_label)

	# 数量
	var count_label: Label = Label.new()
	count_label.text = "x%d" % count
	count_label.add_theme_font_size_override("font_size", 11)
	count_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
	count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(count_label)

	return row


func _update_highlight() -> void:
	for i in range(_rows.size()):
		var row: HBoxContainer = _rows[i] as HBoxContainer
		# 第一个子节点是背景 ColorRect
		var bg: ColorRect = row.get_child(0) as ColorRect
		if i == _selected_index:
			bg.color = Color(0.3, 0.25, 0.5, 0.6)
		else:
			bg.color = Color(0.1, 0.1, 0.14, 0.5)
