extends Node
class_name DialogueRunner

## 对话运行器
## 职责：持有 DialogueResource，调用 get_next_dialogue_line() 推进对话
## 将 DialogueLine 交给 DialogueStage，不直接操作 UI 或 Spine

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
		_dialogue_stage.dialogue_finished.connect(_on_dialogue_finished)


func _unhandled_input(event: InputEvent) -> void:
	if not _is_running:
		return

	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_handle_advance()
			get_viewport().set_input_as_handled()
	elif event is InputEventKey:
		var key: InputEventKey = event as InputEventKey
		if key.pressed and (key.keycode == KEY_SPACE or key.keycode == KEY_ENTER):
			_handle_advance()
			get_viewport().set_input_as_handled()


func start_dialogue(resource: Resource, title: String = "start", config: Dictionary = {}) -> void:
	## 启动对话
	if _dialogue_stage == null:
		push_error("%s No DialogueStage found at path: %s" % [LOG_PREFIX, str(dialogue_stage_path)])
		return

	_dialogue_resource = resource
	_is_running = true

	# 配置会话
	_dialogue_stage.configure_session(config)

	if debug_log:
		print("%s Starting dialogue, title: %s" % [LOG_PREFIX, title])

	dialogue_started.emit()

	# 获取第一行
	_advance_to_next_line(title)


func stop_dialogue() -> void:
	_is_running = false
	if _dialogue_stage != null:
		_dialogue_stage.finish()
	dialogue_ended.emit()

	if debug_log:
		print("%s Dialogue stopped" % LOG_PREFIX)


func _handle_advance() -> void:
	if _dialogue_stage == null:
		return

	# 如果有 responses，不处理推进
	if _current_line != null and "responses" in _current_line:
		var responses: Variant = _current_line.responses
		if responses is Array and responses.size() > 0:
			return

	_dialogue_stage.handle_input_advance()


func _advance_to_next_line(title_or_id: String = "") -> void:
	if _dialogue_resource == null:
		_finish()
		return

	# 调用 DialogueManager 获取下一行
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
		var text: String = str(line.text) if "text" in line else ""
		print("%s Got line: [%s] %s" % [LOG_PREFIX, char_name, text.left(40)])

	# 交给舞台
	_dialogue_stage.present_line(line)


func _on_line_completed() -> void:
	# 推进到下一行
	if _current_line != null and "next_id" in _current_line:
		var next_id: String = str(_current_line.next_id)
		_advance_to_next_line(next_id)
	else:
		_advance_to_next_line()


func _on_dialogue_finished() -> void:
	_is_running = false
	dialogue_ended.emit()


func _finish() -> void:
	_is_running = false
	if _dialogue_stage != null:
		_dialogue_stage.finish()
	dialogue_ended.emit()

	if debug_log:
		print("%s Dialogue ended" % LOG_PREFIX)


func _find_dialogue_manager() -> Object:
	## 查找 DialogueManager autoload（注册为 Engine singleton）
	if Engine.has_singleton("DialogueManager"):
		return Engine.get_singleton("DialogueManager")

	# 兜底：从场景树查找
	var root: Node = get_tree().root
	for child: Node in root.get_children():
		if child.name == "DialogueManager":
			return child
	return null
