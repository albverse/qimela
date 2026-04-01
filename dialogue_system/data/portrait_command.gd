extends RefCounted
class_name PortraitCommand

## 立绘控制指令，由 DialogueStage 构建并发送给 SpinePortraitController

var target_emotion: StringName = &"idle"
var use_talk: bool = true
var after_text: StringName = &"keep"
var resolved_skin: StringName = &""
var light_state: StringName = &"bright"
