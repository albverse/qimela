extends RefCounted
class_name DialogueLineMeta

## 每句对话行解析后的结构化元数据
## 由 DialogueMetaResolver 生成，供 DialogueStage 分发

var speaker_role: StringName = &"other"      ## player / other / narrator
var emotion: StringName = &"idle"            ## 目标情绪（idle / angry / sad / fear）
var use_talk: bool = true                    ## 本句是否播放 talk 动画
var after_text: StringName = &"keep"         ## 打字完成后停留状态：keep = 保持当前情绪
var skin_override: StringName = &""          ## 本句临时皮肤 override（主要用于非玩家角色）
var bubble_style_override: StringName = &""  ## 本句临时气泡样式 override
var speaker_id: StringName = &""             ## 说话者标识（角色名）

## ── 立绘动效 ──
var portrait_effect: StringName = &""        ## 立绘动效命令（fade_in / fade_out / slide_in / slide_out / shake）
var portrait_shader: StringName = &""        ## 立绘附着 shader 标识（由外部注册表映射到实际 ShaderMaterial）

## ── 气泡动效 ──
var bubble_animation: StringName = &""       ## 气泡动效命令（shake / none）
var bubble_material_key: StringName = &""    ## 气泡材质标识（default / explosion / thinking）
