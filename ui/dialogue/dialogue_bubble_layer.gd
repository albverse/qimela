## Dialogic 自定义 Layout Layer：气泡对话层
## 负责连接 Dialogic 信号，驱动 BubbleSlotManager 和 SpinePortraitController
## 使用方式：将此脚本挂载到一个继承 DialogicLayoutLayer 的场景根节点
class_name DialogueBubbleLayer
extends DialogicLayoutLayer

# ── 编辑器可调参数 ──
@export_group("Slot Positions")
@export var player_current_pos: Vector2 = Vector2(150, 300)
@export var other_current_pos: Vector2 = Vector2(620, 90)
@export var player_history_pos: Vector2 = Vector2(150, 120)
@export var other_history_pos: Vector2 = Vector2(620, -70)

@export_group("Animation")
@export var appear_duration: float = 0.25
@export var move_to_history_duration: float = 0.35
@export var fade_out_duration: float = 0.3
@export var history_alpha: float = 0.5

@export_group("Bubble")
@export var bubble_width: float = 400.0
@export var bubble_font_size: int = 22
@export var bubble_padding_top: int = 22
@export var bubble_padding_bottom: int = 50
@export var bubble_padding_side: int = 35
@export var show_speaker_name: bool = false

@export_group("Portraits")
## 玩家立绘控制器（场景中 SpinePortraitController 节点路径）
@export var player_portrait_path: NodePath = NodePath("")
## 对方立绘控制器节点路径
@export var other_portrait_path: NodePath = NodePath("")
## 玩家角色显示名
@export var player_display_name: String = "玩家"
## 对方角色显示名
@export var other_display_name: String = "????"

## 气泡背景贴图（dialogic_text.png）
@export var bubble_texture: Texture2D

# ── 内部状态 ──
var _slot_manager: BubbleSlotManager
var _player_portrait: SpinePortraitController = null
var _other_portrait: SpinePortraitController = null

## 待处理的情绪状态（由 EmotionEvent 提前写入，TextEvent 读取）
var _pending_emotion: Dictionary = {}

## 上一稳定状态（player / other 各自维护）
var _last_stable: Dictionary = {
	&"player": &"idle_loop",
	&"other": &"idle_loop",
}


func _ready() -> void:
	if Engine.is_editor_hint():
		return

	# 创建 BubbleSlotManager（作为子节点挂在此 Layer 下）
	_slot_manager = BubbleSlotManager.new()
	_apply_slot_settings()
	add_child(_slot_manager)

	# 查找立绘控制器
	if player_portrait_path != NodePath(""):
		var n: Node = get_node_or_null(player_portrait_path)
		if n is SpinePortraitController:
			_player_portrait = n as SpinePortraitController
	if other_portrait_path != NodePath(""):
		var n: Node = get_node_or_null(other_portrait_path)
		if n is SpinePortraitController:
			_other_portrait = n as SpinePortraitController

	# 安全连接 Dialogic 信号
	_connect_dialogic()


func _apply_export_overrides() -> void:
	_apply_slot_settings()


func _apply_slot_settings() -> void:
	if _slot_manager == null:
		return
	_slot_manager.player_current_pos = player_current_pos
	_slot_manager.other_current_pos = other_current_pos
	_slot_manager.player_history_pos = player_history_pos
	_slot_manager.other_history_pos = other_history_pos
	_slot_manager.appear_duration = appear_duration
	_slot_manager.move_to_history_duration = move_to_history_duration
	_slot_manager.fade_out_duration = fade_out_duration
	_slot_manager.history_alpha = history_alpha
	_slot_manager.bubble_width = bubble_width
	_slot_manager.bubble_font_size = bubble_font_size
	_slot_manager.bubble_padding_top = bubble_padding_top
	_slot_manager.bubble_padding_bottom = bubble_padding_bottom
	_slot_manager.bubble_padding_side = bubble_padding_side
	_slot_manager.show_speaker_name = show_speaker_name
	if bubble_texture != null:
		_slot_manager.set_bubble_texture(bubble_texture)


## ── Dialogic 信号连接 ──

func _connect_dialogic() -> void:
	var d: Node = get_node_or_null("/root/Dialogic")
	if d == null:
		return
	var text_sub: Variant = d.get("Text")
	if text_sub == null:
		return
	if text_sub.has_signal("about_to_show_text"):
		text_sub.about_to_show_text.connect(_on_about_to_show_text)
	if text_sub.has_signal("text_finished"):
		text_sub.text_finished.connect(_on_text_finished)
	if d.has_signal("signal_event"):
		d.signal_event.connect(_on_dialogic_signal)


## ── Dialogic 信号处理 ──

## 文字即将显示时：推进气泡 + 驱动立绘动画
func _on_about_to_show_text(info: Dictionary) -> void:
	# 读取待处理的情绪数据（由 EmotionEvent 通过 signal_event 提前写入）
	var role: StringName = _pending_emotion.get("speaker_role", &"")
	var emotion: StringName = _pending_emotion.get("emotion", &"idle")
	var use_talk: bool = _pending_emotion.get("use_talk", true)

	# 若无 EmotionEvent 提供角色，从 Dialogic 角色信息推断
	if role == &"":
		role = _resolve_role_from_character(info)
	_pending_emotion.clear()

	# 推进气泡
	var speaker_name: String = _get_display_name(role)
	var text: String = info.get("text", "")
	_slot_manager.advance(role, speaker_name, text)

	# 驱动立绘动画
	var portrait: SpinePortraitController = _get_portrait(role)
	if portrait != null:
		var from_stable: StringName = _last_stable.get(role, &"idle_loop")
		var chain: ExpressionTransitionResolver.AnimChain = ExpressionTransitionResolver.resolve(
			from_stable,
			emotion,
			use_talk,
			portrait.has_animation
		)
		portrait.apply_chain(chain)
		_last_stable[role] = chain.stable_state


## 文字打字结束时：停止说话动画
func _on_text_finished(_info: Dictionary) -> void:
	if _player_portrait != null:
		_player_portrait.on_text_finished()
	if _other_portrait != null:
		_other_portrait.on_text_finished()


## 接收 Dialogic Signal Event（EmotionEvent 通过 signal 传递情绪数据）
func _on_dialogic_signal(arg: Variant) -> void:
	if not (arg is Dictionary):
		return
	var d: Dictionary = arg as Dictionary
	if d.get("type", "") == "emotion":
		_pending_emotion = d.duplicate()


## ── 辅助 ──

## 从 Dialogic 角色信息推断 role（player / other）
func _resolve_role_from_character(info: Dictionary) -> StringName:
	var character: Variant = info.get("character")
	if character != null and character is Resource:
		var char_name: String = character.get("display_name") if character.get("display_name") else ""
		if char_name == player_display_name:
			return &"player"
	return &"other"


func _get_portrait(role: StringName) -> SpinePortraitController:
	if role == &"player":
		return _player_portrait
	return _other_portrait


func _get_display_name(role: StringName) -> String:
	if role == &"player":
		return player_display_name
	return other_display_name


## 外部注册立绘控制器（测试场景直接调用）
func register_portrait(role: StringName, controller: SpinePortraitController) -> void:
	if role == &"player":
		_player_portrait = controller
	else:
		_other_portrait = controller


## 清除所有气泡（转发给 BubbleSlotManager）
func clear_all() -> void:
	if _slot_manager != null:
		_slot_manager.clear_all()


## 外部直接推进对话（不走 Dialogic 时间线，用于测试）
func push_line(role: StringName, emotion: StringName, use_talk: bool, text: String) -> void:
	var speaker_name: String = _get_display_name(role)
	_slot_manager.advance(role, speaker_name, text)

	var portrait: SpinePortraitController = _get_portrait(role)
	if portrait != null:
		var from_stable: StringName = _last_stable.get(role, &"idle_loop")
		var chain: ExpressionTransitionResolver.AnimChain = ExpressionTransitionResolver.resolve(
			from_stable,
			emotion,
			use_talk,
			portrait.has_animation
		)
		portrait.apply_chain(chain)
		_last_stable[role] = chain.stable_state
		# 文字是即时显示，延迟后自动退出 talk
		if use_talk:
			_start_talk_timer(portrait)


func _start_talk_timer(portrait: SpinePortraitController) -> void:
	var timer: SceneTreeTimer = get_tree().create_timer(2.0)
	timer.timeout.connect(portrait.on_text_finished)
