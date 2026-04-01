extends Node2D
class_name DialogueTestScene

## 对话系统测试场景
## 用于验证完整对话 UI 流程：气泡推进、立绘动画、历史缩略
##
## 【美术使用说明】
## 1. 拖动 SlotA / SlotB / SlotC / SlotD (Marker2D) 调整气泡位置
##    A = 对方历史气泡位置，B = 玩家历史气泡位置
##    C = 对方当前气泡位置，D = 玩家当前气泡位置
## 2. 拖动 PlayerPortrait / OtherPortrait 调整立绘位置
## 3. 修改 DialogueBubble.tscn 改变气泡样式
## 4. 左键点击推进对话

const LOG_PREFIX: String = "[DialogueTestScene]"

@export var dialogue_file: Resource = null
@export var start_title: String = "start"
@export var auto_start: bool = true

@onready var dialogue_runner: DialogueRunner = $DialogueRunner
@onready var dialogue_stage: DialogueStage = $DialogueStage
@onready var info_label: Label = $UI/InfoLabel
@onready var restart_button: Button = $UI/RestartButton

var _dialogue_resource: Resource = null


func _ready() -> void:
	dialogue_runner.dialogue_started.connect(_on_dialogue_started)
	dialogue_runner.dialogue_ended.connect(_on_dialogue_ended)
	restart_button.pressed.connect(_on_restart_pressed)

	# 加载对话资源
	if dialogue_file != null:
		_dialogue_resource = dialogue_file
	else:
		_dialogue_resource = load("res://dialogue_test/dialogue_spine_test.dialogue")

	_update_info("按 [Restart] 开始对话\n左键点击推进对话")

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
