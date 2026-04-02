extends RefCounted
class_name PortraitCommand

## 立绘控制指令，由 DialogueStage 构建并发送给 SpinePortraitController

var target_emotion: StringName = &"idle"
var use_talk: bool = true
var after_text: StringName = &"keep"
var resolved_skin: StringName = &""
var light_state: StringName = &"bright"

## ── 动效指令 ──
var portrait_effect: StringName = &""    ## fade_in / fade_out / slide_in / slide_out / shake
var portrait_shader: StringName = &""    ## shader 标识（空字符串 = 不变更）
