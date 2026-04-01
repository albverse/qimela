## Dialogic 对话气泡测试场景
## 启动 Dialogic 时间线，使用自定义双气泡布局
extends Node


func _ready() -> void:
	# 添加深色背景
	var bg: ColorRect = ColorRect.new()
	bg.color = Color(0.10, 0.10, 0.13)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# 启动 Dialogic 时间线
	Dialogic.start("test_bubble")
	Dialogic.timeline_ended.connect(_on_dialogue_ended)


func _on_dialogue_ended() -> void:
	# 对话结束后提示
	var label: Label = Label.new()
	label.text = "对话结束 — 按 ESC 退出"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	label.add_theme_font_size_override("font_size", 28)
	label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	add_child(label)
