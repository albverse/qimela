## Dialogic 自定义 Layout Layer：气泡对话层
## 负责连接 Dialogic 信号，驱动 BubbleSlotManager 和 SpinePortraitController
## 使用方式：将此脚本挂载到一个继承 DialogicLayoutLayer 的场景根节点
class_name DialogueBubbleLayer
extends DialogicLayoutLayer

# ── 编辑器可调参数 ──
@export_group("Slot Positions")
@export var player_current_pos: Vector2 = Vector2(220, 500)
@export var other_current_pos: Vector2 = Vector2(900, 180)
@export var player_history_pos: Vector2 = Vector2(220, 350)
@export var other_history_pos: Vector2 = Vector2(900, 50)

@export_group("Animation")
@export var appear_duration: float = 0.25
@export var move_to_history_duration: float = 0.35
@export var fade_out_duration: float = 0.3
@export var history_alpha: float = 0.5

@export_group("Bubble")
@export var bubble_width: float = 380.0
@export var bubble_font_size: int = 18

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

	# 连接 Dialogic 文字信号（有 Dialogic 时才连接）
	if Dialogic != null and Dialogic.has_method("get") and Dialogic.Text != null:
		if not Dialogic.Text.about_to_show_text.is_connected(_on_about_to_show_text):
			Dialogic.Text.about_to_show_text.connect(_on_about_to_show_text)
		if not Dialogic.Text.text_finished.is_connected(_on_text_finished):
			Dialogic.Text.text_finished.connect(_on_text_finished)
		# 连接 Dialogic 信号事件（接收 EmotionEvent 发来的信号）
		if not Dialogic.signal_event.is_connected(_on_dialogic_signal):
			Dialogic.signal_event.connect(_on_dialogic_signal)


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
	if bubble_texture != null:
		_slot_manager.set_bubble_texture(bubble_texture)


## ── Dialogic 信号处理 ──

## 文字即将显示时：推进气泡 + 驱动立绘动画
func _on_about_to_show_text(info: Dictionary) -> void:
	# 读取待处理的情绪数据（由 EmotionEvent 通过 signal_event 提前写入）
	var role: StringName = _pending_emotion.get("speaker_role", &"other")
	var emotion: StringName = _pending_emotion.get("emotion", &"idle")
	var use_talk: bool = _pending_emotion.get("use_talk", true)
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
