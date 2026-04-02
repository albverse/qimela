extends CanvasLayer
class_name DialogueStage

## 对话舞台主控
## 职责：作为最终演出舞台，管理左右立绘、气泡层、历史层
## 接收 DialogueRunner 分发的行数据，调度各子控制器
## 不自己拼接动画名，不自己解析玩家皮肤命名规则
##
## 【美术使用说明】
## 1. 4个 Marker2D 锚点（SlotA~D）决定气泡位置，直接拖动即可
## 2. PlayerPortrait / OtherPortrait 是独立立绘场景，可单独调整
## 3. BubbleLayer 是气泡父容器
## 4. bubble_scene 指向对话框场景，可替换为不同风格

const LOG_PREFIX: String = "[DialogueStage]"

signal dialogue_line_completed()
signal dialogue_response_selected(next_id: String)
signal dialogue_finished()

@export var debug_log: bool = false

## ── 场景引用 ──
@export_group("Scene References")
@export var bubble_scene: PackedScene = null
@export var player_portrait_path: NodePath = ""
@export var other_portrait_path: NodePath = ""
@export_node_path("Control") var bubble_layer_path: NodePath = NodePath("BubbleLayer")
@export_node_path("Node") var bubble_slot_manager_path: NodePath = NodePath("BubbleSlotManager")
@export_node_path("Control") var responses_layer_path: NodePath = NodePath("ResponsesLayer")
@export_node_path("VBoxContainer") var responses_container_path: NodePath = NodePath("ResponsesLayer/ResponsesContainer")

## ── 皮肤同步开关（美术素材未就绪时关闭） ──
@export_group("Skin Sync")
@export var player_skin_sync_enabled: bool = false
@export var light_state_sync_enabled: bool = false

## 会话配置
var session_config: Dictionary = {}

## 子控制器
var _meta_resolver: DialogueMetaResolver = null
var _bubble_slot_manager: BubbleSlotManager = null
var _style_controller: BubbleStyleController = null
var _skin_resolver: PlayerPortraitSkinResolver = null

## 立绘场景引用
var _player_portrait: SpinePortraitScene = null
var _other_portrait: SpinePortraitScene = null

## 气泡层容器
var _bubble_layer: Control = null

## 当前状态
var _current_meta: DialogueLineMeta = null
var _is_waiting_for_input: bool = false
var _current_light_state: StringName = &"bright"
var _player_node_ref: Node = null
var _portraits_entered: bool = false
var _dialogue_active: bool = false
var _responses_layer: Control = null
var _responses_container: VBoxContainer = null
var _current_line: Object = null
var _has_ended: bool = false


func _ready() -> void:
	_bubble_layer = get_node_or_null(bubble_layer_path) as Control
	_player_portrait = get_node_or_null(player_portrait_path) as SpinePortraitScene
	_other_portrait = get_node_or_null(other_portrait_path) as SpinePortraitScene
	_responses_layer = get_node_or_null(responses_layer_path) as Control
	_responses_container = get_node_or_null(responses_container_path) as VBoxContainer

	_init_controllers()
	_ensure_responses_ui()
	_hide_responses()
	process_mode = Node.PROCESS_MODE_ALWAYS

	if debug_log:
		print("%s Ready" % LOG_PREFIX)


func _init_controllers() -> void:
	_meta_resolver = DialogueMetaResolver.new()
	_meta_resolver.debug_log = debug_log

	_style_controller = BubbleStyleController.new()
	_style_controller.debug_log = debug_log

	_bubble_slot_manager = get_node_or_null(bubble_slot_manager_path) as BubbleSlotManager
	if _bubble_slot_manager == null:
		_bubble_slot_manager = BubbleSlotManager.new()
		_bubble_slot_manager.name = "BubbleSlotManager"
		add_child(_bubble_slot_manager)
	_bubble_slot_manager.debug_log = debug_log
	_bubble_slot_manager.setup(_bubble_layer, bubble_scene, _style_controller)
	_bubble_slot_manager.bubble_typing_finished.connect(_on_typing_finished)

	_skin_resolver = PlayerPortraitSkinResolver.new()
	_skin_resolver.debug_log = debug_log


func configure_session(config: Dictionary) -> void:
	session_config = config
	_has_ended = false

	if config.has("character_role_map"):
		_meta_resolver.character_role_map = config["character_role_map"]

	if config.has("player_bubble_style"):
		_style_controller.set_default_player_texture(config["player_bubble_style"])
	if config.has("other_bubble_style"):
		_style_controller.set_default_other_texture(config["other_bubble_style"])

	# 支持通过 config 注册额外气泡纹理
	if config.has("bubble_textures") and config["bubble_textures"] is Dictionary:
		var textures: Dictionary = config["bubble_textures"]
		for key: String in textures:
			_style_controller.register_texture(key, textures[key])

	# 支持通过 config 注册气泡材质
	if config.has("bubble_materials") and config["bubble_materials"] is Dictionary:
		var materials: Dictionary = config["bubble_materials"]
		for key: String in materials:
			_style_controller.register_material(key, materials[key])

	# 支持通过 config 注册立绘 shader
	if config.has("portrait_shaders") and config["portrait_shaders"] is Dictionary:
		var shaders: Dictionary = config["portrait_shaders"]
		if _player_portrait != null:
			for key: String in shaders:
				_player_portrait.register_shader(key, shaders[key])
		if _other_portrait != null:
			for key: String in shaders:
				_other_portrait.register_shader(key, shaders[key])

	if config.has("light_state"):
		_current_light_state = StringName(config["light_state"])

	if config.has("player_node"):
		_player_node_ref = config["player_node"]

	# 播放立绘入场动画
	_play_portraits_enter()

	if debug_log:
		print("%s Session configured" % LOG_PREFIX)


func present_line(line: Object) -> void:
	_current_line = line
	_hide_responses()

	# 1. 解析元数据
	_current_meta = _meta_resolver.resolve(line)

	# 2. 构建气泡数据
	var payload: BubblePayload = BubblePayload.new()
	payload.full_text = str(line.text) if "text" in line else ""
	payload.speaker_role = _current_meta.speaker_role
	payload.speaker_name = str(_current_meta.speaker_id)
	payload.bubble_style_id = _current_meta.bubble_style_override
	payload.bubble_animation = _current_meta.bubble_animation
	payload.bubble_material_key = _current_meta.bubble_material_key
	payload.history_preview_text = BubblePayload.build_history_preview_text(
		payload.full_text,
		_bubble_slot_manager.history_preview_char_count,
		_bubble_slot_manager.history_preview_suffix
	)

	# 3. 显示气泡
	_bubble_slot_manager.show_bubble(payload)

	# 4. 驱动立绘动画
	if light_state_sync_enabled:
		_current_light_state = _resolve_light_state()
	_drive_portrait(_current_meta)

	# 5. 驱动立绘动效命令（shader / 抖动 / 淡入淡出等）
	_apply_portrait_effect(_current_meta)

	# 6. 等待输入
	_is_waiting_for_input = false

	if debug_log:
		print("%s Presented line: [%s] %s" % [
			LOG_PREFIX, _current_meta.speaker_id, payload.full_text.left(40)
		])


func handle_input_advance() -> bool:
	if _has_responses(_current_line):
		return false

	if _bubble_slot_manager.is_any_typing():
		_bubble_slot_manager.skip_current_typing()
		return false

	if _is_waiting_for_input:
		_stop_current_talk()
		_is_waiting_for_input = false
		dialogue_line_completed.emit()
		return true

	return false


func finish() -> void:
	if _has_ended:
		return
	_has_ended = true

	_bubble_slot_manager.clear_all()
	_hide_responses()
	_current_line = null
	_is_waiting_for_input = false
	if _player_portrait != null:
		_player_portrait.reset_controller()
	if _other_portrait != null:
		_other_portrait.reset_controller()
	_portraits_entered = false
	dialogue_finished.emit()

	if debug_log:
		print("%s Dialogue finished" % LOG_PREFIX)


func set_dialogue_active(active: bool) -> void:
	_dialogue_active = active
	if active:
		_has_ended = false
	else:
		_hide_responses()
		_is_waiting_for_input = false


## ── 内部：立绘入场 ──

func _play_portraits_enter() -> void:
	if _portraits_entered:
		return
	_portraits_entered = true

	if _player_portrait != null:
		_player_portrait.setup_controller()
		_player_portrait.play_slide_in()
	if _other_portrait != null:
		_other_portrait.setup_controller()
		_other_portrait.play_slide_in()

	_emit_sfx_portrait_changed()


## ── 内部：立绘驱动 ──

func _drive_portrait(meta: DialogueLineMeta) -> void:
	var portrait: SpinePortraitScene = _get_portrait_for_role(meta.speaker_role)
	if portrait == null or portrait.portrait_controller == null:
		return

	var command: PortraitCommand = PortraitCommand.new()
	command.target_emotion = meta.emotion
	command.use_talk = meta.use_talk
	command.after_text = meta.after_text
	command.light_state = _current_light_state
	command.portrait_effect = meta.portrait_effect
	command.portrait_shader = meta.portrait_shader

	# 皮肤解析（仅在启用时生效）
	if meta.speaker_role == &"player" and player_skin_sync_enabled and meta.skin_override == &"":
		command.resolved_skin = _skin_resolver.resolve(
			_player_node_ref, _current_light_state
		)
	elif meta.skin_override != &"":
		command.resolved_skin = meta.skin_override

	portrait.portrait_controller.execute_command(command)


func _apply_portrait_effect(meta: DialogueLineMeta) -> void:
	## 分发立绘动效命令（shader 附着 / 抖动 / 淡入淡出等）
	var portrait: SpinePortraitScene = _get_portrait_for_role(meta.speaker_role)
	if portrait == null:
		return

	# Shader 附着
	if meta.portrait_shader != &"":
		portrait.apply_shader(meta.portrait_shader)

	# 动效命令
	if meta.portrait_effect != &"":
		portrait.play_effect(meta.portrait_effect)
		_emit_sfx_portrait_changed()


func _get_portrait_for_role(role: StringName) -> SpinePortraitScene:
	if role == &"player":
		return _player_portrait
	return _other_portrait


func _stop_current_talk() -> void:
	if _current_meta == null:
		return
	var portrait: SpinePortraitScene = _get_portrait_for_role(_current_meta.speaker_role)
	if portrait != null and portrait.portrait_controller != null:
		portrait.portrait_controller.stop_talk()


func _on_typing_finished() -> void:
	if _has_responses(_current_line):
		_show_responses_for_line(_current_line)
		_is_waiting_for_input = false
		_stop_current_talk()
		return

	_is_waiting_for_input = true
	_stop_current_talk()

	if debug_log:
		print("%s Typing finished, waiting for input" % LOG_PREFIX)


## ── 输入处理 ──

func _input(event: InputEvent) -> void:
	if not _dialogue_active:
		return

	# 对话激活时：左键推进对话，其他所有输入全部吞掉
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			# responses 显示时不处理左键推进（让按钮接收点击）
			if _responses_layer != null and _responses_layer.visible and _has_responses(_current_line):
				return
			handle_input_advance()
		get_viewport().set_input_as_handled()
	else:
		# 吞掉所有非鼠标左键事件：键盘、手柄、触摸等
		get_viewport().set_input_as_handled()


## ── Responses 系统 ──

func _has_responses(line: Object) -> bool:
	if line == null or not ("responses" in line):
		return false
	var responses: Variant = line.responses
	return responses is Array and responses.size() > 0


func _resolve_light_state() -> StringName:
	if _player_node_ref != null:
		if _player_node_ref.has_method("get_dialogue_light_state"):
			return StringName(str(_player_node_ref.get_dialogue_light_state()))
		if "dialogue_light_state" in _player_node_ref:
			return StringName(str(_player_node_ref.dialogue_light_state))
	if session_config.has("light_state"):
		return StringName(session_config["light_state"])
	return _current_light_state


func _ensure_responses_ui() -> void:
	if _responses_layer != null and _responses_container != null:
		return

	_responses_layer = Control.new()
	_responses_layer.name = "ResponsesLayer"
	_responses_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_responses_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_responses_layer)

	_responses_container = VBoxContainer.new()
	_responses_container.name = "ResponsesContainer"
	_responses_container.anchor_left = 0.5
	_responses_container.anchor_right = 0.5
	_responses_container.anchor_top = 1.0
	_responses_container.anchor_bottom = 1.0
	_responses_container.offset_left = -280.0
	_responses_container.offset_right = 280.0
	_responses_container.offset_top = -280.0
	_responses_container.offset_bottom = -40.0
	_responses_container.mouse_filter = Control.MOUSE_FILTER_STOP
	_responses_container.alignment = BoxContainer.ALIGNMENT_END
	_responses_container.add_theme_constant_override("separation", 8)
	_responses_layer.add_child(_responses_container)


func _show_responses_for_line(line: Object) -> void:
	if _responses_layer == null or _responses_container == null or not _has_responses(line):
		return

	for child: Node in _responses_container.get_children():
		child.queue_free()

	var responses: Array = line.responses
	for idx: int in range(responses.size()):
		var response: Object = responses[idx]
		var btn: Button = Button.new()
		btn.text = str(response.text) if "text" in response else "Option %d" % (idx + 1)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.mouse_filter = Control.MOUSE_FILTER_STOP
		btn.pressed.connect(_on_response_button_pressed.bind(response))
		_responses_container.add_child(btn)

	_responses_layer.visible = true


func _hide_responses() -> void:
	if _responses_layer != null:
		_responses_layer.visible = false
	if _responses_container != null:
		for child: Node in _responses_container.get_children():
			child.queue_free()


func _on_response_button_pressed(response: Object) -> void:
	_hide_responses()
	_is_waiting_for_input = false
	_stop_current_talk()
	var next_id: String = str(response.next_id) if "next_id" in response else ""
	dialogue_response_selected.emit(next_id)


## ── SFX 钩子 ──

func _emit_sfx_portrait_changed() -> void:
	var bus: Node = _get_event_bus()
	if bus != null and bus.has_method("emit_dialogue_sfx_portrait_changed"):
		bus.emit_dialogue_sfx_portrait_changed()


func _get_event_bus() -> Node:
	if Engine.has_singleton("EventBus"):
		return Engine.get_singleton("EventBus") as Node
	var root: Node = get_tree().root if get_tree() != null else null
	if root != null:
		return root.get_node_or_null("EventBus")
	return null
