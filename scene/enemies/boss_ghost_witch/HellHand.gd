## 地狱之手：在玩家地面位置出现 → appear 动画 → capture_check 事件判定 → hold/close
## 生命周期：APPEAR → (spine capture_check) → HOLD/CLOSING → queue_free
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

var _current_anim_name: StringName = &""
var _current_anim_loop: bool = false


func _ready() -> void:
	species_id = &"hell_hand"
	has_hp = false
	super._ready()
	add_to_group("hell_hand")

	_spine = get_node_or_null("SpineSprite")
	_capture_area = get_node_or_null("CaptureArea")
	_hit_area = get_node_or_null("HitArea")

	if _spine != null:
		if _spine.has_signal("animation_completed"):
			_spine.animation_completed.connect(_on_anim_completed_raw)
		if _spine.has_signal("animation_event"):
			_spine.animation_event.connect(_on_spine_event)
		print("[HELL_HAND] _ready: spine ok pos=%s" % global_position)
	else:
		print("[HELL_HAND] _ready: SpineSprite NOT found!")

	if _hit_area != null:
		_hit_area.area_entered.connect(_on_hit_area_entered)

	_play_anim(&"appear", false)
	print("[HELL_HAND] _ready complete: state=APPEAR pos=%s" % global_position)


func setup(player: Node2D, boss: BossGhostWitch, stun_time: float) -> void:
	_player = player
	_boss = boss
	_stun_time = stun_time
	print("[HELL_HAND] setup: player=%s stun_time=%.1f" % [player, stun_time])


# ═══ Spine 事件回调（capture_check 是唯一的捕获触发源）═══

func _on_spine_event(a1 = null, a2 = null, a3 = null, a4 = null) -> void:
	var event_name := _extract_spine_event_name(a1, a2, a3, a4)
	if event_name == &"capture_check":
		if _state != HandState.APPEAR or _player_captured:
			return
		print("[HELL_HAND] capture_check: testing player overlap...")
		if _is_player_in_capture_area():
			print("[HELL_HAND] capture_check: HIT → capture")
			_capture_player()
		else:
			print("[HELL_HAND] capture_check: MISS → CLOSING")
			_state = HandState.CLOSING
			_play_anim(&"close", false)


func _on_anim_completed_raw(a1 = null, a2 = null, a3 = null) -> void:
	pass  # 状态转换由 _physics_process 轮询驱动


# ═══ _physics_process ═══

func _physics_process(_dt: float) -> void:
	if Engine.get_physics_frames() % 60 == 0:
		print("[HELL_HAND_DIAG] state=%d captured=%s anim=%s pos=%s player=%s" % [
			_state, _player_captured, _current_anim_name, global_position,
			_player.global_position if _player != null and is_instance_valid(_player) else "null"
		])

	match _state:
		HandState.APPEAR:
			# appear 动画播完但 capture_check 未触发/未捕获 → 关闭
			if _is_current_anim_finished() and not _player_captured:
				print("[HELL_HAND] APPEAR: anim done, not captured → CLOSING")
				_state = HandState.CLOSING
				_play_anim(&"close", false)

		HandState.HOLD:
			if Time.get_ticks_msec() >= _imprison_end:
				print("[HELL_HAND] HOLD: stun expired (%.1fs) → release + CLOSING" % _stun_time)
				_release_player()
				_state = HandState.CLOSING
				_play_anim(&"close", false)

		HandState.CLOSING:
			if _is_current_anim_finished():
				print("[HELL_HAND] CLOSING: done → queue_free")
				_cleanup_and_free()


# ═══ 击碎检测 ═══

func _on_hit_area_entered(area: Area2D) -> void:
	if area == null:
		return
	if area.is_in_group("ghost_fist_hitbox") or area.is_in_group("run_slash_hitbox"):
		print("[HELL_HAND] hit_area: %s → release + CLOSING" % area.name)
		_release_player()
		_state = HandState.CLOSING
		_play_anim(&"close", false)


func apply_hit(hit: HitData) -> bool:
	if hit == null:
		return false
	if hit.weapon_id == &"ghost_fist" or hit.weapon_id == &"run_slash":
		print("[HELL_HAND] apply_hit: %s → release + CLOSING" % hit.weapon_id)
		_release_player()
		_state = HandState.CLOSING
		_play_anim(&"close", false)
		return true
	return false


func force_release() -> void:
	if _state == HandState.HOLD or _state == HandState.APPEAR:
		print("[HELL_HAND] force_release → release + CLOSING")
		_release_player()
		_state = HandState.CLOSING
		_play_anim(&"close", false)


# ═══ 捕获/释放 ═══

func _is_player_in_capture_area() -> bool:
	# 优先 Area2D
	if _capture_area != null:
		for body in _capture_area.get_overlapping_bodies():
			if body != null and body.is_in_group("player"):
				print("[HELL_HAND] capture_area: found player")
				return true
	# 备用距离检测（Area2D 可能因时序未生效）
	if _player != null and is_instance_valid(_player):
		var dist: float = global_position.distance_to(_player.global_position)
		print("[HELL_HAND] capture_area: area2d miss, dist=%.1f" % dist)
		if dist <= 80.0:
			return true
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
	print("[HELL_HAND] captured: stun=%.1fs" % _stun_time)


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


# ═══ 动画 ═══

func _play_anim(anim_name: StringName, loop: bool) -> void:
	_current_anim_name = anim_name
	_current_anim_loop = loop
	if _spine == null:
		return
	var anim_state: Object = _get_anim_state()
	if anim_state == null:
		return
	if anim_state.has_method("set_animation"):
		anim_state.set_animation(String(anim_name), loop, 0)
	elif anim_state.has_method("setAnimation"):
		anim_state.setAnimation(String(anim_name), loop, 0)


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
