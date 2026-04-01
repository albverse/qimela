extends Node2D
class_name DialogueTestScene

## 对话系统测试场景
## 用于验证完整对话 UI 流程：气泡推进、立绘动画、历史缩略

const LOG_PREFIX: String = "[DialogueTestScene]"

@export var dialogue_file: Resource = null
@export var start_title: String = "start"
@export var auto_start: bool = true

@onready var dialogue_runner: DialogueRunner = $DialogueRunner
@onready var dialogue_stage: DialogueStage = $DialogueStage
@onready var player_portrait: SpinePortraitScene = $DialogueStage/StageRoot/PortraitLayer/PlayerPortrait
@onready var other_portrait: SpinePortraitScene = $DialogueStage/StageRoot/PortraitLayer/OtherPortrait
@onready var info_label: Label = $UI/InfoLabel
@onready var restart_button: Button = $UI/RestartButton

var _dialogue_resource: Resource = null


func _ready() -> void:
	# 连接信号
	dialogue_runner.dialogue_started.connect(_on_dialogue_started)
	dialogue_runner.dialogue_ended.connect(_on_dialogue_ended)
	restart_button.pressed.connect(_on_restart_pressed)

	# 初始化立绘
	if player_portrait != null:
		player_portrait.setup_controller()
	if other_portrait != null:
		other_portrait.setup_controller()

	# 加载对话资源
	if dialogue_file != null:
		_dialogue_resource = dialogue_file
	else:
		# 尝试从文件路径加载
		_dialogue_resource = load("res://dialogue_test/dialogue_spine_test.dialogue")

	_update_info("按 [Restart] 开始对话\n左键/空格 推进对话")

	if auto_start:
		call_deferred("_start_test")


func _start_test() -> void:
	if _dialogue_resource == null:
		_update_info("ERROR: 无法加载对话资源")
		return

	var config: Dictionary = {
		"character_role_map": {
			"Hero": "player",
			"Cultist": "other",
			"Nathan": "other",
		},
		"light_state": "bright",
	}

	dialogue_runner.start_dialogue(_dialogue_resource, start_title, config)


func _on_dialogue_started() -> void:
	_update_info("对话进行中...\n左键/空格 推进")
	restart_button.disabled = true


func _on_dialogue_ended() -> void:
	_update_info("对话结束\n按 [Restart] 重新开始")
	restart_button.disabled = false


func _on_restart_pressed() -> void:
	# 清理并重新开始
	dialogue_stage.finish()
	call_deferred("_start_test")


func _update_info(text: String) -> void:
	if info_label != null:
		info_label.text = text
