## 自定义 Dialogic 事件：情绪控制事件
## 在文字事件之前放置，传递本句的情绪/说话/角色配置
## 通过 Dialogic.signal_event 发送结构化数据给 DialogueBubbleLayer
@tool
class_name DialogicEmotionEvent
extends DialogicEvent


## 发言方角色：player / other / narrator
@export var speaker_role: StringName = &"other"
## 目标情绪：idle / angry / sad 等
@export var emotion: StringName = &"idle"
## 本句是否播放说话动画
@export var use_talk: bool = true
## 文字结束后的状态：keep（保持当前情绪）或指定情绪
@export var after_text: StringName = &"keep"
## 临时皮肤 override（主要用于非玩家角色，空字符串表示不覆盖）
@export var skin_override: StringName = &""
## 临时气泡样式 override（空字符串表示不覆盖）
@export var bubble_style_override: StringName = &""


#region EXECUTE
################################################################################

func _execute() -> void:
	# 通过 Dialogic.signal_event 发送情绪数据
	# DialogueBubbleLayer 监听此信号并缓存到 _pending_emotion
	var data: Dictionary = {
		"type": "emotion",
		"speaker_role": speaker_role,
		"emotion": emotion,
		"use_talk": use_talk,
		"after_text": after_text,
		"skin_override": skin_override,
		"bubble_style_override": bubble_style_override,
	}
	dialogic.emit_signal("signal_event", data)
	finish()

#endregion


#region INITIALIZE
################################################################################

func _init() -> void:
	event_name = "Emotion"
	event_description = "设置下一句台词的情绪、说话动画和角色配置。"
	set_default_color("Color8")
	event_category = "Dialogue"
	event_sorting_index = 5

#endregion


#region SAVING/LOADING
################################################################################

func get_shortcode() -> String:
	return "emotion"


func get_shortcode_parameters() -> Dictionary:
	return {
		"role":   {"property": "speaker_role",        "default": &"other"},
		"emo":    {"property": "emotion",             "default": &"idle"},
		"talk":   {"property": "use_talk",            "default": true},
		"after":  {"property": "after_text",          "default": &"keep"},
		"skin":   {"property": "skin_override",       "default": &""},
		"bubble": {"property": "bubble_style_override","default": &""},
	}

#endregion


#region EDITOR REPRESENTATION
################################################################################

func build_event_editor() -> void:
	add_header_edit("speaker_role", ValueType.FIXED_OPTIONS, {
		"left_text": "角色:",
		"options": [
			{"label": "player",   "value": &"player"},
			{"label": "other",    "value": &"other"},
			{"label": "narrator", "value": &"narrator"},
		]
	})
	add_header_edit("emotion", ValueType.SINGLELINE_TEXT, {"left_text": "情绪:"})
	add_header_edit("use_talk", ValueType.BOOL, {"left_text": "说话动画:"})
	add_body_edit("after_text",          ValueType.SINGLELINE_TEXT, {"left_text": "文字结束后:"})
	add_body_edit("skin_override",       ValueType.SINGLELINE_TEXT, {"left_text": "皮肤覆盖:"})
	add_body_edit("bubble_style_override", ValueType.SINGLELINE_TEXT, {"left_text": "气泡样式覆盖:"})

#endregion
