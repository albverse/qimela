extends Node2D
class_name DialogueTestScene

## 对话系统测试场景
## 用于验证完整对话 UI 流程：气泡推进、立绘动画、历史缩略、动效命令、shader、responses
##
## 【美术使用说明】
## 1. 拖动 SlotA / SlotB / SlotC / SlotD (Marker2D) 调整气泡位置
## 2. 拖动 PlayerPortrait / OtherPortrait 调整立绘位置
## 3. 修改 DialogueBubble.tscn 改变气泡样式
## 4. 在 SpinePortrait 的 AnimationPlayer 中添加自定义动画，即可通过 [#portrait_effect=动画名] 调用
## 5. 在 dialogue_system/shaders/ 中添加 ShaderMaterial，注册到 config 后即可通过 [#portrait_shader=key] 调用
## 6. 左键点击推进对话

const LOG_PREFIX: String = "[DialogueTestScene]"

@export var dialogue_file: Resource = null
@export var test_skeleton_data: Resource = null
@export var start_title: String = "start"
@export var auto_start: bool = true

## 立绘闪烁 Shader（在编辑器中赋值或通过 preload 加载）
@export var blink_shader_material: ShaderMaterial = null

@onready var dialogue_runner: DialogueRunner = $DialogueRunner
@onready var dialogue_stage: DialogueStage = $DialogueStage
@onready var player_portrait: SpinePortraitScene = $DialogueStage/PlayerPortrait
@onready var other_portrait: SpinePortraitScene = $DialogueStage/OtherPortrait
@onready var info_label: Label = $UI/InfoLabel
@onready var restart_button: Button = $UI/RestartButton

var _dialogue_resource: Resource = null


func _ready() -> void:
	dialogue_runner.dialogue_started.connect(_on_dialogue_started)
	dialogue_runner.dialogue_ended.connect(_on_dialogue_ended)
	restart_button.pressed.connect(_on_restart_pressed)
	_apply_test_portrait_assets()
	_load_shader_resources()

	# 加载对话资源
	if dialogue_file != null:
		_dialogue_resource = dialogue_file
	else:
		_dialogue_resource = load("res://dialogue_test/dialogue_spine_test.dialogue")

	_update_info("按 [Restart] 开始对话\n左键点击推进对话")

	if auto_start:
		call_deferred("_start_test")


func _apply_test_portrait_assets() -> void:
	if test_skeleton_data == null:
		return

	var player_sprite: Node = player_portrait.get_spine_sprite() if player_portrait != null else null
	var other_sprite: Node = other_portrait.get_spine_sprite() if other_portrait != null else null

	if player_sprite != null and "skeleton_data_res" in player_sprite:
		player_sprite.skeleton_data_res = test_skeleton_data
	if other_sprite != null and "skeleton_data_res" in other_sprite:
		other_sprite.skeleton_data_res = test_skeleton_data


func _load_shader_resources() -> void:
	## 加载 shader 资源（如果编辑器未赋值则尝试 preload）
	if blink_shader_material == null:
		var mat: Resource = load("res://dialogue_system/shaders/portrait_blink_material.tres")
		if mat is ShaderMaterial:
			blink_shader_material = mat as ShaderMaterial


func _start_test() -> void:
	if _dialogue_resource == null:
		_update_info("ERROR: 无法加载对话资源")
		return

	# 构建 session config，注册全部资源
	var config: Dictionary = {
		"character_role_map": {
			"Hero": "player",
			"Cultist": "other",
			"Nathan": "other",
			"Narrator": "narrator",
		},
		"light_state": "bright",
		# 立绘 Shader 注册（在 dialogue 中通过 [#portrait_shader=blink] 引用）
		"portrait_shaders": {},
	}

	# 注册闪烁 shader
	if blink_shader_material != null:
		config["portrait_shaders"]["blink"] = blink_shader_material

	dialogue_runner.start_dialogue(_dialogue_resource, start_title, config)


func _on_dialogue_started() -> void:
	_update_info("对话进行中...\n左键点击推进")
	restart_button.disabled = true


func _on_dialogue_ended() -> void:
	_update_info("对话结束\n按 [Restart] 重新开始")
	restart_button.disabled = false


func _on_restart_pressed() -> void:
	dialogue_stage.finish()
	call_deferred("_start_test")


func _update_info(text: String) -> void:
	if info_label != null:
		info_label.text = text
