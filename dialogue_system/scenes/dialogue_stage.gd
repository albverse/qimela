extends CanvasLayer
class_name DialogueStage

## 对话舞台主控
## 职责：作为最终演出舞台，管理左右立绘、气泡层、历史层
## 接收 DialogueRunner 分发的行数据，调度各子控制器
## 不自己拼接动画名，不自己解析玩家皮肤命名规则

const LOG_PREFIX: String = "[DialogueStage]"

signal dialogue_line_completed()
signal dialogue_finished()

@export var debug_log: bool = false
@export var bubble_scene: PackedScene = null

## 节点引用
@export var player_portrait_path: NodePath = ""
@export var other_portrait_path: NodePath = ""

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


func _ready() -> void:
	_bubble_layer = $BubbleLayer as Control
	_player_portrait = get_node_or_null(player_portrait_path) as SpinePortraitScene
	_other_portrait = get_node_or_null(other_portrait_path) as SpinePortraitScene

	_init_controllers()

	if debug_log:
		print("%s Ready" % LOG_PREFIX)


func _init_controllers() -> void:
	# 元数据解析器
	_meta_resolver = DialogueMetaResolver.new()
	_meta_resolver.debug_log = debug_log

	# 样式控制器
	_style_controller = BubbleStyleController.new()
	_style_controller.debug_log = debug_log

	# 气泡槽位管理器
	_bubble_slot_manager = $BubbleSlotManager as BubbleSlotManager
	if _bubble_slot_manager == null:
		_bubble_slot_manager = BubbleSlotManager.new()
		_bubble_slot_manager.name = "BubbleSlotManager"
		add_child(_bubble_slot_manager)
	_bubble_slot_manager.debug_log = debug_log
	_bubble_slot_manager.setup(_bubble_layer, bubble_scene, _style_controller)
	_bubble_slot_manager.bubble_typing_finished.connect(_on_typing_finished)

	# 玩家皮肤解析器
	_skin_resolver = PlayerPortraitSkinResolver.new()
	_skin_resolver.debug_log = debug_log

	# 立绘控制器由外部（测试场景或游戏场景）调用 setup_controller()
	# 这里不重复初始化


func configure_session(config: Dictionary) -> void:
	## 对话开始时配置会话参数
	session_config = config

	# 角色 → role 映射
	if config.has("character_role_map"):
		_meta_resolver.character_role_map = config["character_role_map"]

	# 气泡样式
	if config.has("player_bubble_style"):
		_style_controller.player_bubble_texture_path = config["player_bubble_style"]
	if config.has("other_bubble_style"):
		_style_controller.other_bubble_texture_path = config["other_bubble_style"]

	# 亮暗状态
	if config.has("light_state"):
		_current_light_state = StringName(config["light_state"])

	# 玩家节点引用
	if config.has("player_node"):
		_player_node_ref = config["player_node"]

	if debug_log:
		print("%s Session configured" % LOG_PREFIX)


func present_line(line: Object) -> void:
	## 接收一行对话数据，驱动演出
	# 1. 解析元数据
	_current_meta = _meta_resolver.resolve(line)

	# 2. 构建气泡数据
	var payload: BubblePayload = BubblePayload.new()
	payload.full_text = str(line.text) if "text" in line else ""
	payload.speaker_role = _current_meta.speaker_role
	payload.bubble_style_id = _current_meta.bubble_style_override
	payload.history_preview_text = BubblePayload.build_history_preview_text(
		payload.full_text,
		_bubble_slot_manager.history_preview_char_count,
		_bubble_slot_manager.history_preview_suffix
	)

	# 3. 显示气泡
	_bubble_slot_manager.show_bubble(payload)

	# 4. 驱动立绘
	_drive_portrait(_current_meta)

	# 5. 等待输入
	_is_waiting_for_input = false

	if debug_log:
		print("%s Presented line: [%s] %s" % [
			LOG_PREFIX, _current_meta.speaker_id, payload.full_text.left(40)
		])


func handle_input_advance() -> bool:
	## 处理玩家推进输入，返回 true 表示可以进入下一句
	if _bubble_slot_manager.is_any_typing():
		# 第一次按：跳过打字
		_bubble_slot_manager.skip_current_typing()
		return false

	if _is_waiting_for_input:
		# 第二次按：进入下一句
		_stop_current_talk()
		_is_waiting_for_input = false
		dialogue_line_completed.emit()
		return true

	return false


func finish() -> void:
	## 对话结束时清理
	_bubble_slot_manager.clear_all()
	_is_waiting_for_input = false
	dialogue_finished.emit()

	if debug_log:
		print("%s Dialogue finished" % LOG_PREFIX)


## ── 内部：立绘驱动 ──

func _drive_portrait(meta: DialogueLineMeta) -> void:
	var portrait: SpinePortraitScene = null
	if meta.speaker_role == &"player":
		portrait = _player_portrait
	else:
		portrait = _other_portrait

	if portrait == null or portrait.portrait_controller == null:
		return

	# 构建立绘指令
	var command: PortraitCommand = PortraitCommand.new()
	command.target_emotion = meta.emotion
	command.use_talk = meta.use_talk
	command.after_text = meta.after_text
	command.light_state = _current_light_state

	# 皮肤解析
	if meta.speaker_role == &"player" and meta.skin_override == &"":
		command.resolved_skin = _skin_resolver.resolve(
			_player_node_ref, _current_light_state
		)
	elif meta.skin_override != &"":
		command.resolved_skin = meta.skin_override

	# 执行
	portrait.portrait_controller.execute_command(command)


func _stop_current_talk() -> void:
	## 停止当前角色 talk 动画
	if _current_meta == null:
		return

	var portrait: SpinePortraitScene = null
	if _current_meta.speaker_role == &"player":
		portrait = _player_portrait
	else:
		portrait = _other_portrait

	if portrait != null and portrait.portrait_controller != null:
		portrait.portrait_controller.stop_talk()


func _on_typing_finished() -> void:
	_is_waiting_for_input = true
	_stop_current_talk()

	if debug_log:
		print("%s Typing finished, waiting for input" % LOG_PREFIX)
