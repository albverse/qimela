extends Node
class_name BubbleSlotManager

## 气泡槽位管理器
## 职责：管理四个固定槽位的气泡生命周期、位置、透明度、历史推进
## 不读取 Dialogue 文件，不控制 Spine 动画
##
## 使用方式：在场景中放置 4 个 Marker2D 作为槽位锚点，
## 美术只需拖动 Marker2D 即可改变气泡出现/移动的位置。
## 当前区（C/D）同一时刻只保留一个气泡。
## 支持视口百分比定位（自动适配分辨率）或 Marker2D 定位两种模式。

const LOG_PREFIX: String = "[BubbleSlot]"

signal bubble_typing_finished()

@export var debug_log: bool = false

## ── 槽位锚点（Marker2D 模式，美术拖动即可调整） ──
@export_group("Slot Anchors")
@export_node_path("Marker2D") var slot_a_other_history_path: NodePath = NodePath("")
@export_node_path("Marker2D") var slot_b_player_history_path: NodePath = NodePath("")
@export_node_path("Marker2D") var slot_c_other_current_path: NodePath = NodePath("")
@export_node_path("Marker2D") var slot_d_player_current_path: NodePath = NodePath("")

## ── 视口百分比定位（自动适配分辨率，优先级高于 Marker2D） ──
@export_group("Viewport-Relative Slots")
## 启用基于视口百分比的槽位定位
@export var viewport_relative_enabled: bool = false
## 各槽位百分比坐标（x=水平百分比, y=垂直百分比, 0.0~1.0）
@export var slot_a_percent: Vector2 = Vector2(0.14, 0.11)
@export var slot_b_percent: Vector2 = Vector2(0.61, 0.11)
@export var slot_c_percent: Vector2 = Vector2(0.08, 0.44)
@export var slot_d_percent: Vector2 = Vector2(0.55, 0.44)

## 运行时解析后的锚点引用
var _slot_a: Marker2D = null
var _slot_b: Marker2D = null
var _slot_c: Marker2D = null
var _slot_d: Marker2D = null

## ── 动画参数（编辑器可调） ──
@export_group("Animation")
## 气泡入场持续时间
@export var bubble_enter_duration: float = 0.3
## 当前气泡移动到历史区的持续时间
@export var bubble_to_history_duration: float = 0.4
## 历史气泡淡出持续时间
@export var history_fadeout_duration: float = 0.3
## 历史气泡透明度（0~1）
@export_range(0.0, 1.0) var history_opacity: float = 0.5

## ── 气泡入场滑入参数 ──
@export_group("Bubble Slide-In")
## 气泡入场滑入偏移距离（像素）
@export var bubble_slide_in_offset: float = 50.0
## 气泡入场滑入角度（度数，0=纯水平，正值=向下倾斜）
@export var bubble_slide_in_angle: float = 15.0

## ── 历史文本缩略参数 ──
@export_group("History Text")
## 触发缩略的字符阈值
@export var history_shrink_threshold: int = 100
## 历史气泡显示的最大字符数
@export var history_preview_char_count: int = 20
## 历史缩略后缀
@export var history_preview_suffix: String = "……"

## ── 打字机 ──
@export_group("Typewriter")
## 打字机每秒字符数
@export var typewriter_speed: float = 30.0

## 气泡场景引用
var bubble_scene: PackedScene = null

## 样式控制器引用
var style_controller: BubbleStyleController = null

## 气泡父容器
var _slots_container: Control = null

## 当前唯一的活跃气泡（CD区同一时刻只有一个）
var _current_bubble: DialogueBubble = null
var _current_bubble_role: StringName = &""
var _current_full_text: String = ""

## 历史气泡（最多一个）
var _history_bubble: DialogueBubble = null
var _history_bubble_role: StringName = &""


func setup(container: Control, scene: PackedScene, style_ctrl: BubbleStyleController) -> void:
	_slots_container = container
	bubble_scene = scene
	style_controller = style_ctrl

	# 解析 Marker2D 锚点
	if slot_a_other_history_path != NodePath(""):
		_slot_a = get_node_or_null(slot_a_other_history_path) as Marker2D
	if slot_b_player_history_path != NodePath(""):
		_slot_b = get_node_or_null(slot_b_player_history_path) as Marker2D
	if slot_c_other_current_path != NodePath(""):
		_slot_c = get_node_or_null(slot_c_other_current_path) as Marker2D
	if slot_d_player_current_path != NodePath(""):
		_slot_d = get_node_or_null(slot_d_player_current_path) as Marker2D

	if debug_log:
		print("%s Setup: A=%s B=%s C=%s D=%s, viewport_relative=%s" % [
			LOG_PREFIX,
			str(_slot_a != null), str(_slot_b != null),
			str(_slot_c != null), str(_slot_d != null),
			str(viewport_relative_enabled),
		])


func show_bubble(payload: BubblePayload) -> void:
	## 显示新的当前气泡
	## 核心逻辑：CD区只保留一个气泡，旧气泡移入对应历史区
	var new_role: StringName = payload.speaker_role

	# 1. 淡出销毁旧的历史气泡
	_fadeout_and_destroy(_history_bubble)
	_history_bubble = null
	_history_bubble_role = &""

	# 2. 当前气泡 → 历史区
	if _current_bubble != null:
		_history_bubble = _current_bubble
		_history_bubble_role = _current_bubble_role
		var history_pos: Vector2 = _get_history_slot_position(_current_bubble_role)
		_move_to_history(_history_bubble, history_pos, _current_bubble_role, _current_full_text)
		_emit_sfx_bubble_to_history()

	# 3. 创建新的当前气泡
	_current_full_text = payload.full_text
	_current_bubble_role = new_role
	var current_pos: Vector2 = _get_current_slot_position(new_role)
	_current_bubble = _create_bubble(payload, current_pos, new_role)
	_emit_sfx_bubble_appeared()

	if debug_log:
		print("%s Bubble [%s] at slot %s, text: %s" % [
			LOG_PREFIX, new_role,
			"D" if new_role == &"player" else "C",
			payload.full_text.left(30)
		])


func skip_current_typing() -> void:
	if _current_bubble != null and _current_bubble.is_typing():
		_current_bubble.skip_typing()


func is_any_typing() -> bool:
	if _current_bubble != null and _current_bubble.is_typing():
		return true
	return false


func clear_all() -> void:
	_destroy_bubble(_current_bubble)
	_destroy_bubble(_history_bubble)
	_current_bubble = null
	_history_bubble = null
	_current_bubble_role = &""
	_history_bubble_role = &""


## ── 槽位位置读取 ──

func _get_current_slot_position(role: StringName) -> Vector2:
	## D = 玩家当前，C = 对方当前
	if viewport_relative_enabled:
		var vp_size: Vector2 = _get_viewport_size()
		if role == &"player":
			return slot_d_percent * vp_size
		return slot_c_percent * vp_size

	if role == &"player" and _slot_d != null:
		return _slot_d.global_position
	elif role != &"player" and _slot_c != null:
		return _slot_c.global_position
	return Vector2(400, 300)


func _get_history_slot_position(role: StringName) -> Vector2:
	## B = 玩家历史，A = 对方历史
	if viewport_relative_enabled:
		var vp_size: Vector2 = _get_viewport_size()
		if role == &"player":
			return slot_b_percent * vp_size
		return slot_a_percent * vp_size

	if role == &"player" and _slot_b != null:
		return _slot_b.global_position
	elif role != &"player" and _slot_a != null:
		return _slot_a.global_position
	return Vector2(400, 80)


func _get_viewport_size() -> Vector2:
	var vp: Viewport = get_viewport()
	if vp != null:
		return Vector2(vp.get_visible_rect().size)
	return Vector2(1280, 720)


## ── 气泡创建与动画 ──

func _create_bubble(
	payload: BubblePayload,
	slot_position: Vector2,
	role: StringName
) -> DialogueBubble:
	if bubble_scene == null:
		push_error("%s bubble_scene is null!" % LOG_PREFIX)
		return null

	var bubble: DialogueBubble = bubble_scene.instantiate() as DialogueBubble
	_slots_container.add_child(bubble)

	# 设置说话者名字
	bubble.set_speaker_name(payload.speaker_name)

	# 应用样式（纹理 + 材质）
	if style_controller != null:
		style_controller.apply_style_to_bubble(
			bubble, role, payload.bubble_style_id, payload.bubble_material_key
		)

	# 计算居中目标位置（使用 custom_minimum_size 做初始估算）
	var half_size: Vector2 = bubble.custom_minimum_size * 0.5
	var target_pos: Vector2 = slot_position - half_size

	# 入场动画：从说话者方向斜向滑入 + 淡入
	var slide_dir: float = -1.0 if role == &"player" else 1.0
	var angle_rad: float = deg_to_rad(bubble_slide_in_angle)
	var slide_offset: Vector2 = Vector2(
		bubble_slide_in_offset * slide_dir,
		-bubble_slide_in_offset * sin(angle_rad)
	)

	bubble.modulate.a = 0.0
	bubble.global_position = target_pos + slide_offset

	var tw: Tween = bubble.create_tween()
	tw.set_parallel(true)
	tw.tween_property(
		bubble, "global_position", target_pos, bubble_enter_duration
	).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(
		bubble, "modulate:a", 1.0, bubble_enter_duration
	).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)

	# 显示文本（打字机效果）
	bubble.show_with_typewriter(payload, typewriter_speed)
	bubble.typing_finished.connect(_on_bubble_typing_finished, CONNECT_ONE_SHOT)

	# 播放气泡动效（如抖动）
	if payload.bubble_animation != &"":
		_apply_bubble_effect(bubble, payload.bubble_animation)

	return bubble


func _move_to_history(
	bubble: DialogueBubble,
	history_position: Vector2,
	role: StringName,
	full_text: String
) -> void:
	if bubble == null:
		return

	# 断开打字完成信号
	if bubble.typing_finished.is_connected(_on_bubble_typing_finished):
		bubble.typing_finished.disconnect(_on_bubble_typing_finished)

	# 如果还在打字，直接完成
	if bubble.is_typing():
		bubble.skip_typing()

	# 历史文本缩略
	var preview_text: String = full_text
	if full_text.length() > history_shrink_threshold:
		preview_text = BubblePayload.build_history_preview_text(
			full_text, history_preview_char_count, history_preview_suffix
		)
	bubble.convert_to_history(preview_text)

	# 应用历史样式
	if style_controller != null:
		style_controller.apply_history_style(bubble, role)

	# 平滑移动到历史位置（居中对齐）
	var half_size: Vector2 = bubble.size * 0.5
	if half_size == Vector2.ZERO:
		half_size = bubble.custom_minimum_size * 0.5
	var centered_history_pos: Vector2 = history_position - half_size

	var tw: Tween = bubble.create_tween()
	tw.set_parallel(true)
	tw.tween_property(
		bubble, "global_position", centered_history_pos, bubble_to_history_duration
	).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(
		bubble, "modulate:a", history_opacity, bubble_to_history_duration
	)


func _fadeout_and_destroy(bubble: DialogueBubble) -> void:
	if bubble == null:
		return

	if bubble.typing_finished.is_connected(_on_bubble_typing_finished):
		bubble.typing_finished.disconnect(_on_bubble_typing_finished)

	var tw: Tween = bubble.create_tween()
	tw.tween_property(bubble, "modulate:a", 0.0, history_fadeout_duration)
	tw.finished.connect(bubble.queue_free)


func _destroy_bubble(bubble: DialogueBubble) -> void:
	if bubble != null and is_instance_valid(bubble):
		bubble.queue_free()


func _apply_bubble_effect(bubble: DialogueBubble, effect_name: StringName) -> void:
	## 应用气泡动效（延迟到入场动画结束后执行）
	match str(effect_name):
		"shake":
			get_tree().create_timer(bubble_enter_duration).timeout.connect(bubble.play_shake)
		_:
			bubble.play_custom_animation(str(effect_name))


func _on_bubble_typing_finished() -> void:
	bubble_typing_finished.emit()
	if debug_log:
		print("%s Typing finished" % LOG_PREFIX)


## ── SFX 钩子 ──

func _emit_sfx_bubble_appeared() -> void:
	var bus: Node = _get_event_bus()
	if bus != null and bus.has_method("emit_dialogue_sfx_bubble_appeared"):
		bus.emit_dialogue_sfx_bubble_appeared()


func _emit_sfx_bubble_to_history() -> void:
	var bus: Node = _get_event_bus()
	if bus != null and bus.has_method("emit_dialogue_sfx_bubble_to_history"):
		bus.emit_dialogue_sfx_bubble_to_history()


func _get_event_bus() -> Node:
	if Engine.has_singleton("EventBus"):
		return Engine.get_singleton("EventBus") as Node
	var root: Node = get_tree().root if get_tree() != null else null
	if root != null:
		return root.get_node_or_null("EventBus")
	return null
