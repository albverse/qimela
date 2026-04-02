extends Node
class_name DialogueRunner

## 对话运行器
## 职责：持有 DialogueResource，调用 get_next_dialogue_line() 推进对话
## 将 DialogueLine 交给 DialogueStage，不直接操作 UI 或 Spine
##
## 对话期间通过 EventBus 广播输入锁定请求，由 player / inventory 等系统自行订阅处理
## 仅负责流程推进，不参与 UI 渲染

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
var _is_advancing: bool = false  ## 防重入锁


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
	_is_advancing = false

	_dialogue_stage.configure_session(config)
	_dialogue_stage.set_dialogue_active(true)

	# 广播输入锁定请求
	_emit_input_lock(true)

	if debug_log:
		print("%s Starting dialogue, title: %s" % [LOG_PREFIX, title])

	dialogue_started.emit()
	_advance_to_next_line(title)


func stop_dialogue() -> void:
	if not _is_running:
		return
	_is_running = false
	_is_advancing = false
	if _dialogue_stage != null:
		_dialogue_stage.set_dialogue_active(false)
		_dialogue_stage.finish()
	# finish() 会通过 dialogue_finished 信号触发 _on_dialogue_finished
	# 但 _on_dialogue_finished 中有 _is_running 保护，不会重复 emit


func is_running() -> bool:
	return _is_running


func _advance_to_next_line(title_or_id: String = "") -> void:
	if _dialogue_resource == null:
		_finish()
		return

	# 防重入：await 期间不允许再次进入
	if _is_advancing:
		if debug_log:
			print("%s Advance blocked: already advancing" % LOG_PREFIX)
		return
	_is_advancing = true

	var dm: Object = _find_dialogue_manager()
	if dm == null:
		push_error("%s DialogueManager not found!" % LOG_PREFIX)
		_is_advancing = false
		_finish()
		return

	var line: Object = await dm.get_next_dialogue_line(
		_dialogue_resource, title_or_id, []
	)

	_is_advancing = false

	if not _is_running:
		return

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
	if not _is_running:
		return
	if _current_line != null and "next_id" in _current_line:
		var next_id: String = str(_current_line.next_id)
		_advance_to_next_line(next_id)
	else:
		_advance_to_next_line()


func _on_dialogue_finished() -> void:
	## 由 DialogueStage.finish() → dialogue_finished 信号触发
	## 防止与 _finish() 重复 emit dialogue_ended
	if not _is_running:
		return
	_is_running = false
	_is_advancing = false
	if _dialogue_stage != null:
		_dialogue_stage.set_dialogue_active(false)
	_emit_input_lock(false)
	dialogue_ended.emit()

	if debug_log:
		print("%s Dialogue ended (via stage finished)" % LOG_PREFIX)


func _on_response_selected(next_id: String) -> void:
	if not _is_running:
		return
	_advance_to_next_line(next_id)


func _finish() -> void:
	if not _is_running:
		return
	_is_running = false
	_is_advancing = false
	if _dialogue_stage != null:
		_dialogue_stage.set_dialogue_active(false)
		_dialogue_stage.finish()
		# finish() 触发 dialogue_finished → _on_dialogue_finished
		# 但此时 _is_running 已为 false，不会重复 emit
	_emit_input_lock(false)
	dialogue_ended.emit()

	if debug_log:
		print("%s Dialogue ended" % LOG_PREFIX)


## ── 输入锁定广播 ──

func _emit_input_lock(locked: bool) -> void:
	var bus: Node = _get_event_bus()
	if bus == null:
		return
	if locked:
		if bus.has_method("emit_dialogue_input_lock_requested"):
			bus.emit_dialogue_input_lock_requested()
	else:
		if bus.has_method("emit_dialogue_input_lock_released"):
			bus.emit_dialogue_input_lock_released()


func _get_event_bus() -> Node:
	if Engine.has_singleton("EventBus"):
		return Engine.get_singleton("EventBus") as Node
	var root: Node = get_tree().root if get_tree() != null else null
	if root != null:
		return root.get_node_or_null("EventBus")
	return null


func _find_dialogue_manager() -> Object:
	if Engine.has_singleton("DialogueManager"):
		return Engine.get_singleton("DialogueManager")

	var root: Node = get_tree().root
	for child: Node in root.get_children():
		if child.name == "DialogueManager":
			return child
	return null
