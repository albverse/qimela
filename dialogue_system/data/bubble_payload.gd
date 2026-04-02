extends RefCounted
class_name BubblePayload

## 气泡视图数据，由 BubbleSlotManager 消费
## 包含完整文本与历史缩略文本

var full_text: String = ""
var history_preview_text: String = ""
var speaker_role: StringName = &"other"
var speaker_name: String = ""
var bubble_style_id: StringName = &""
var is_history: bool = false

## ── 动效与材质 ──
var bubble_animation: StringName = &""       ## 气泡动效命令（shake / none）
var bubble_material_key: StringName = &""    ## 气泡材质标识（default / explosion / thinking）


## 构建历史缩略文本
static func build_history_preview_text(
	source_text: String,
	preview_char_count: int = 20,
	suffix: String = "……"
) -> String:
	if source_text.length() <= preview_char_count:
		return source_text
	return source_text.left(preview_char_count) + suffix
