class_name DropConfirmDialogUI
extends PanelContainer

## 丢弃确认对话框
## 在 OtherItems 面板中选中物品后按 E 弹出
## E = 确认丢弃, B/Esc = 取消

const DIALOG_WIDTH: float = 220.0

var _message_label: Label = null
var _hint_label: Label = null
var _inventory: PlayerInventory = null
var _pending_index: int = -1
var _pending_item_id: StringName = &""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(DIALOG_WIDTH, 0)
	visible = false

	# 样式
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.08, 0.18, 0.95)
	style.border_color = Color(0.8, 0.4, 0.4, 0.8)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(12)
	add_theme_stylebox_override("panel", style)

	# 居中
	set_anchors_preset(Control.PRESET_CENTER)
	offset_left = -DIALOG_WIDTH * 0.5
	offset_right = DIALOG_WIDTH * 0.5
	offset_top = -40.0
	offset_bottom = 40.0

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vbox)

	_message_label = Label.new()
	_message_label.add_theme_font_size_override("font_size", 13)
	_message_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.7))
	_message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(_message_label)

	_hint_label = Label.new()
	_hint_label.text = "[E] 确认丢弃　[B] 取消"
	_hint_label.add_theme_font_size_override("font_size", 10)
	_hint_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_hint_label)


func set_inventory(inv: PlayerInventory) -> void:
	_inventory = inv


func show_for_item(item_name: String, item_id: StringName, other_index: int) -> void:
	## 显示丢弃确认
	_pending_index = other_index
	_pending_item_id = item_id
	_message_label.text = "确认丢弃「%s」？" % item_name
	visible = true


func confirm_drop() -> int:
	## 执行丢弃，返回错误码
	if _inventory == null or _pending_index < 0:
		visible = false
		return PlayerInventory.UseError.ERR_STATE_BLOCKED

	var err: int = _inventory.try_drop_other_item(_pending_index)
	visible = false
	_pending_index = -1
	return err


func cancel() -> void:
	visible = false
	_pending_index = -1


func is_showing() -> bool:
	return visible
