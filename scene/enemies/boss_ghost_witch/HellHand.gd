## 地狱之手：在玩家位置出现 → 短暂 appear → 抓住玩家 → hold 直到释放条件
## 生命周期：APPEAR → HOLD → CLOSING → queue_free
## 释放条件：ghostfist 攻击 / run_slash 命中 / 5秒超时
extends MonsterBase
class_name HellHand

enum HandState { APPEAR, HOLD, CLOSING }

var _state: int = HandState.APPEAR
var _player: Node2D = null
var _boss: BossGhostWitch = null
var _imprison_end: int = 0
var _stun_time: float = 5.0
var _player_captured: bool = false

var _spine: Node = null
var _capture_area: Area2D = null
var _hit_area: Area2D = null

# 当前播放的动画名和完成状态（轮询用）
var _current_anim_name: StringName = &""
var _current_anim_loop: bool = false

# 捕获计时：appear 动画播放一段后自动捕获
var _appear_elapsed: float = 0.0
const CAPTURE_TIME: float = 0.2  # appear 播放 0.2s 后自动捕获玩家
const CAPTURE_RADIUS: float = 80.0  # 捕获判定半径（px）


func _ready() -> void:
	species_id = &"hell_hand"
	has_hp = false
	super._ready()
	add_to_group("hell_hand")

	_spine = get_node_or_null("SpineSprite")
	_capture_area = get_node_or_null("CaptureArea")
	_hit_area = get_node_or_null("HitArea")

	if _spine != null:
		var has_completed := _spine.has_signal("animation_completed")
		var has_event := _spine.has_signal("animation_event")
		print("[HELL_HAND] _ready: spine=%s completed_sig=%s event_sig=%s pos=%s" % [_spine.get_class(), has_completed, has_event, global_position])
		if has_completed:
			_spine.animation_completed.connect(_on_anim_completed_raw)
		if has_event:
			_spine.animation_event.connect(_on_spine_event)
	else:
		print("[HELL_HAND] _ready: SpineSprite NOT found! children=%s" % _list_children())

	# 连接 HitArea 用于 ghostfist 击碎检测
	if _hit_area != null:
		_hit_area.area_entered.connect(_on_hit_area_entered)

	_appear_elapsed = 0.0
	_play_anim(&"appear", false)
	print("[HELL_HAND] _ready complete: state=APPEAR pos=%s" % global_position)


func setup(player: Node2D, boss: BossGhostWitch, stun_time: float) -> void:
	_player = player
	_boss = boss
	_stun_time = stun_time
	print("[HELL_HAND] setup: player=%s boss=%s stun_time=%.1f" % [player, boss, stun_time])


# ═══ Spine 事件回调 ═══

func _on_spine_event(a1 = null, a2 = null, a3 = null, a4 = null) -> void:
	var event_name := _extract_spine_event_name(a1, a2, a3, a4)
	print("[HELL_HAND] spine_event: %s state=%d captured=%s" % [event_name, _state, _player_captured])
	if event_name == &"capture_check" and _state == HandState.APPEAR and not _player_captured:
		_try_capture()


func _on_anim_completed_raw(a1 = null, a2 = null, a3 = null) -> void:
	var anim_name := _extract_completed_anim_name(a1, a2, a3)
	print("[HELL_HAND] anim_completed: %s state=%d" % [anim_name, _state])


# ═══ _physics_process：轮询驱动状态机 ═══

func _physics_process(_dt: float) -> void:
	if Engine.get_physics_frames() % 60 == 0:
		print("[HELL_HAND_DIAG] state=%d captured=%s anim=%s pos=%s player=%s" % [
			_state, _player_captured, _current_anim_name, global_position,
			_player.global_position if _player != null and is_instance_valid(_player) else "null"
		])

	match _state:
		HandState.APPEAR:
			_appear_elapsed += _dt
			# 在 CAPTURE_TIME 后自动尝试捕获（HellHand 生成在玩家位置，几乎必中）
			if not _player_captured and _appear_elapsed >= CAPTURE_TIME:
				if _try_capture():
					return
				# 如果捕获失败（玩家已闪避），等 appear 动画播完后关闭
				if _is_current_anim_finished():
					print("[HELL_HAND] APPEAR: capture failed, anim done → CLOSING")
					_state = HandState.CLOSING
					_play_anim(&"close", false)

		HandState.HOLD:
			# 唯一的自动释放条件：超时
			if Time.get_ticks_msec() >= _imprison_end:
				print("[HELL_HAND] HOLD: stun expired (%.1fs) → release + CLOSING" % _stun_time)
				_release_player()
				_state = HandState.CLOSING
				_play_anim(&"close", false)

		HandState.CLOSING:
			if _is_current_anim_finished():
				print("[HELL_HAND] CLOSING: close done → queue_free")
				_cleanup_and_free()


# ═══ 击碎检测（ghostfist / run_slash 通过 HitArea 或 apply_hit）═══

func _on_hit_area_entered(area: Area2D) -> void:
	if area == null:
		return
	# ghostfist 或 run_slash 的攻击范围进入 HitArea
	if area.is_in_group("ghost_fist_hitbox") or area.is_in_group("run_slash_hitbox"):
		print("[HELL_HAND] hit_area_entered: %s → release + CLOSING" % area.name)
		_release_player()
		_state = HandState.CLOSING
		_play_anim(&"close", false)


func apply_hit(hit: HitData) -> bool:
	# ghostfist 或 run_slash 都可以击碎 HellHand
	if hit == null:
		return false
	if hit.weapon_id == &"ghost_fist" or hit.weapon_id == &"run_slash":
		print("[HELL_HAND] apply_hit: %s → release + CLOSING" % hit.weapon_id)
		_release_player()
		_state = HandState.CLOSING
		_play_anim(&"close", false)
		return true
	return false


## Boss 的 run_slash 经过时直接调用此方法释放
func force_release() -> void:
	if _state == HandState.HOLD or _state == HandState.APPEAR:
		print("[HELL_HAND] force_release → release + CLOSING")
		_release_player()
		_state = HandState.CLOSING
		_play_anim(&"close", false)


# ═══ 捕获/释放玩家 ═══

func _try_capture() -> bool:
	if _player_captured:
		return true
	if _player == null or not is_instance_valid(_player):
		print("[HELL_HAND] _try_capture: no valid player")
		return false

	# 优先用 Area2D 检测
	var captured := false
	if _capture_area != null:
		for body in _capture_area.get_overlapping_bodies():
			if body != null and body.is_in_group("player"):
				captured = true
				break

	# 备用：距离检测
	if not captured:
		var dist: float = global_position.distance_to(_player.global_position)
		print("[HELL_HAND] _try_capture: area2d miss, dist=%.1f radius=%.1f" % [dist, CAPTURE_RADIUS])
		if dist <= CAPTURE_RADIUS:
			captured = true

	if captured:
		_capture_player()
		print("[HELL_HAND] _try_capture: SUCCESS pos=%s player_pos=%s" % [global_position, _player.global_position])
		return true

	print("[HELL_HAND] _try_capture: FAILED pos=%s player_pos=%s" % [global_position, _player.global_position])
	return false


func _capture_player() -> void:
	_state = HandState.HOLD
	_player_captured = true
	_imprison_end = Time.get_ticks_msec() + int(_stun_time * 1000.0)
	_play_anim(&"hold", true)
	if _player != null and is_instance_valid(_player) and _player.has_method("set_external_control_frozen"):
		_player.call("set_external_control_frozen", true)
	if _boss != null and is_instance_valid(_boss):
		_boss._player_imprisoned = true
	print("[HELL_HAND] captured: stun=%.1fs end=%d" % [_stun_time, _imprison_end])


func _release_player() -> void:
	if _player_captured:
		print("[HELL_HAND] _release_player: unfreezing")
	_player_captured = false
	if _player != null and is_instance_valid(_player) and _player.has_method("set_external_control_frozen"):
		_player.call("set_external_control_frozen", false)
	if _boss != null and is_instance_valid(_boss):
		_boss._player_imprisoned = false


func _cleanup_and_free() -> void:
	_release_player()
	queue_free()


func _exit_tree() -> void:
	_release_player()


# ═══ 动画播放 + 轮询完成检测 ═══

func _play_anim(anim_name: StringName, loop: bool) -> void:
	_current_anim_name = anim_name
	_current_anim_loop = loop
	if _spine == null:
		print("[HELL_HAND] _play_anim: spine NULL, skip %s" % anim_name)
		return
	var anim_state: Object = _get_anim_state()
	if anim_state == null:
		print("[HELL_HAND] _play_anim: anim_state NULL, skip %s" % anim_name)
		return
	if anim_state.has_method("set_animation"):
		anim_state.set_animation(String(anim_name), loop, 0)
	elif anim_state.has_method("setAnimation"):
		anim_state.setAnimation(String(anim_name), loop, 0)
	print("[HELL_HAND] _play_anim: %s loop=%s" % [anim_name, loop])


func _is_current_anim_finished() -> bool:
	if _current_anim_loop:
		return false
	if _spine == null:
		return true
	var anim_state: Object = _get_anim_state()
	if anim_state == null:
		return true
	var entry: Object = null
	if anim_state.has_method("get_current"):
		entry = anim_state.get_current(0)
	if entry == null:
		return true
	if entry.has_method("is_complete"):
		return entry.is_complete()
	elif entry.has_method("isComplete"):
		return entry.isComplete()
	return false


func _get_anim_state() -> Object:
	if _spine == null:
		return null
	if _spine.has_method("get_animation_state"):
		return _spine.get_animation_state()
	elif _spine.has_method("getAnimationState"):
		return _spine.getAnimationState()
	return null


func _list_children() -> String:
	var names: Array[String] = []
	for c in get_children():
		names.append(c.name)
	return str(names)


# ═══ Spine 事件名/动画名提取 ═══

func _extract_spine_event_name(a1 = null, a2 = null, a3 = null, a4 = null) -> StringName:
	var spine_event: Object = null
	for a in [a1, a2, a3, a4]:
		if a == null:
			continue
		if a is Object and a.has_method("get_data"):
			spine_event = a
			break
	if spine_event == null:
		return &""
	var data: Object = spine_event.get_data()
	if data == null:
		return &""
	var event_name: String = ""
	if data.has_method("get_event_name"):
		event_name = data.get_event_name()
	elif data.has_method("getEventName"):
		event_name = data.getEventName()
	elif data.has_method("get_name"):
		event_name = data.get_name()
	elif data.has_method("getName"):
		event_name = data.getName()
	if event_name == "":
		return &""
	return StringName(event_name)


func _extract_completed_anim_name(a1 = null, a2 = null, a3 = null) -> StringName:
	var entry: Object = null
	for a in [a1, a2, a3]:
		if a == null:
			continue
		if a is Object and a.has_method("get_animation"):
			entry = a
			break
		if a is Object and a.has_method("getAnimation"):
			entry = a
			break
	if entry == null:
		return &""
	var anim: Object = null
	if entry.has_method("get_animation"):
		anim = entry.get_animation()
	elif entry.has_method("getAnimation"):
		anim = entry.getAnimation()
	if anim == null:
		return &""
	var name_str: String = ""
	if anim.has_method("get_name"):
		name_str = anim.get_name()
	elif anim.has_method("getName"):
		name_str = anim.getName()
	if name_str == "":
		return &""
	return StringName(name_str)
