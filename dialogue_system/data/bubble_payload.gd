extends RefCounted
class_name BubblePayload

## 气泡视图数据，由 BubbleSlotManager 消费
## 包含完整文本与历史缩略文本

var full_text: String = ""
var history_preview_text: String = ""
var speaker_role: StringName = &"other"
var bubble_style_id: StringName = &""
var is_history: bool = false


## 构建历史缩略文本
static func build_history_preview_text(
	source_text: String,
	preview_char_count: int = 20,
	suffix: String = "……"
) -> String:
	if source_text.length() <= preview_char_count:
		return source_text
	return source_text.left(preview_char_count) + suffix
