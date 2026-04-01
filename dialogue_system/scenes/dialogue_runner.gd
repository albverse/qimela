extends Node
class_name DialogueRunner

## 对话运行器
## 职责：持有 DialogueResource，调用 get_next_dialogue_line() 推进对话
## 将 DialogueLine 交给 DialogueStage，不直接操作 UI 或 Spine
##
## 输入：仅左键点击推进对话，对话期间吞掉所有输入防止玩家操作

const LOG_PREFIX: String = "[DialogueRunner]"

signal dialogue_started()
signal dialogue_ended()

@export var debug_log: bool = false
@export var dialogue_stage_path: NodePath = ""

## 对话资源
var _dialogue_resource: Resource = null
var _dialogue_stage: DialogueStage = null
var _is_running: bool = false
var _current_line: Object = null


func _ready() -> void:
	_dialogue_stage = get_node_or_null(dialogue_stage_path) as DialogueStage
	if _dialogue_stage != null:
		_dialogue_stage.dialogue_line_completed.connect(_on_line_completed)
		_dialogue_stage.dialogue_response_selected.connect(_on_response_selected)
		_dialogue_stage.dialogue_finished.connect(_on_dialogue_finished)


func start_dialogue(resource: Resource, title: String = "start", config: Dictionary = {}) -> void:
	if _dialogue_stage == null:
		push_error("%s No DialogueStage found at path: %s" % [LOG_PREFIX, str(dialogue_stage_path)])
		return

	_dialogue_resource = resource
	_is_running = true

	_dialogue_stage.configure_session(config)
	_dialogue_stage.set_dialogue_active(true)

	if debug_log:
		print("%s Starting dialogue, title: %s" % [LOG_PREFIX, title])

	dialogue_started.emit()
	_advance_to_next_line(title)


func stop_dialogue() -> void:
	_is_running = false
	if _dialogue_stage != null:
		_dialogue_stage.set_dialogue_active(false)
		_dialogue_stage.finish()
	dialogue_ended.emit()

	if debug_log:
		print("%s Dialogue stopped" % LOG_PREFIX)


func is_running() -> bool:
	return _is_running


func _advance_to_next_line(title_or_id: String = "") -> void:
	if _dialogue_resource == null:
		_finish()
		return

	var dm: Object = _find_dialogue_manager()
	if dm == null:
		push_error("%s DialogueManager not found!" % LOG_PREFIX)
		_finish()
		return

	var line: Object = await dm.get_next_dialogue_line(
		_dialogue_resource, title_or_id, []
	)

	if line == null:
		_finish()
		return

	_current_line = line

	if debug_log:
		var char_name: String = str(line.character) if "character" in line else "???"
		var text_preview: String = str(line.text).left(40) if "text" in line else ""
		print("%s Got line: [%s] %s" % [LOG_PREFIX, char_name, text_preview])

	_dialogue_stage.present_line(line)


func _on_line_completed() -> void:
	if _current_line != null and "next_id" in _current_line:
		var next_id: String = str(_current_line.next_id)
		_advance_to_next_line(next_id)
	else:
		_advance_to_next_line()


func _on_dialogue_finished() -> void:
	_is_running = false
	if _dialogue_stage != null:
		_dialogue_stage.set_dialogue_active(false)
	dialogue_ended.emit()


func _on_response_selected(next_id: String) -> void:
	_advance_to_next_line(next_id)


func _finish() -> void:
	_is_running = false
	if _dialogue_stage != null:
		_dialogue_stage.set_dialogue_active(false)
		_dialogue_stage.finish()
	dialogue_ended.emit()

	if debug_log:
		print("%s Dialogue ended" % LOG_PREFIX)


func _find_dialogue_manager() -> Object:
	if Engine.has_singleton("DialogueManager"):
		return Engine.get_singleton("DialogueManager")

	var root: Node = get_tree().root
	for child: Node in root.get_children():
		if child.name == "DialogueManager":
			return child
	return null
