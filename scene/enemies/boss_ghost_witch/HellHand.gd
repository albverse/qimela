extends MonsterBase
class_name HellHand

enum HandState { APPEAR, HOLD, CLOSING }

var _state: int = HandState.APPEAR
var _player: Node2D = null
var _boss: BossGhostWitch = null
var _imprison_end: int = 0
var _stun_time: float = 3.0
var _player_captured: bool = false

var _spine: Node = null
var _capture_area: Area2D = null

func _ready() -> void:
	species_id = &"hell_hand"
	has_hp = false
	super._ready()
	add_to_group("hell_hand")

	_spine = get_node_or_null("SpineSprite")
	_capture_area = get_node_or_null("CaptureArea")
	if _spine != null:
		var has_completed := _spine.has_signal("animation_completed")
		var has_event := _spine.has_signal("animation_event")
		print("[HELL_HAND_DEBUG] _ready: spine found, animation_completed=%s animation_event=%s pos=%s" % [has_completed, has_event, global_position])
		if has_completed:
			_spine.animation_completed.connect(_on_anim_completed_raw)
		if has_event:
			_spine.animation_event.connect(_on_spine_event)
	else:
		print("[HELL_HAND_DEBUG] _ready: SpineSprite NOT found! pos=%s" % global_position)
	_play_anim(&"appear", false)


func setup(player: Node2D, boss: BossGhostWitch, stun_time: float) -> void:
	_player = player
	_boss = boss
	_stun_time = stun_time


func _on_spine_event(a1 = null, a2 = null, a3 = null, a4 = null) -> void:
	var event_name := _extract_spine_event_name(a1, a2, a3, a4)
	print("[HELL_HAND_DEBUG] spine_event: name=%s state=%d" % [event_name, _state])
	if event_name != &"capture_check":
		return
	if _is_player_in_capture_area():
		print("[HELL_HAND_DEBUG] capture_check: player IN area → capture + hold")
		_capture_player()
		_play_anim(&"hold", true)
	else:
		print("[HELL_HAND_DEBUG] capture_check: player NOT in area → close")
		_state = HandState.CLOSING
		_play_anim(&"close", false)


func _physics_process(_dt: float) -> void:
	if _state == HandState.HOLD and Time.get_ticks_msec() >= _imprison_end:
		_release_player()
		_state = HandState.CLOSING
		_play_anim(&"close", false)


func _on_anim_completed_raw(a1 = null, a2 = null, a3 = null) -> void:
	var anim_name := _extract_completed_anim_name(a1, a2, a3)
	print("[HELL_HAND_DEBUG] anim_completed: name=%s state=%d captured=%s" % [anim_name, _state, _player_captured])
	if anim_name == &"appear" and not _player_captured:
		print("[HELL_HAND_DEBUG] appear done, not captured → close")
		_state = HandState.CLOSING
		_play_anim(&"close", false)
	elif anim_name == &"close":
		print("[HELL_HAND_DEBUG] close done → queue_free")
		_release_player()
		queue_free()


func apply_hit(hit: HitData) -> bool:
	if hit == null or hit.weapon_id != &"ghost_fist":
		return false
	_release_player()
	_state = HandState.CLOSING
	_play_anim(&"close", false)
	return true


func _capture_player() -> void:
	_state = HandState.HOLD
	_player_captured = true
	_imprison_end = Time.get_ticks_msec() + int(_stun_time * 1000.0)
	if _player != null and _player.has_method("set_external_control_frozen"):
		_player.call("set_external_control_frozen", true)
	if _boss != null:
		_boss._player_imprisoned = true


func _is_player_in_capture_area() -> bool:
	if _capture_area == null:
		return _player != null and global_position.distance_to(_player.global_position) < 64.0
	for body in _capture_area.get_overlapping_bodies():
		if body != null and body.is_in_group("player"):
			return true
	return false


func _release_player() -> void:
	if _player != null and _player.has_method("set_external_control_frozen"):
		_player.call("set_external_control_frozen", false)
	if _boss != null:
		_boss._player_imprisoned = false


func _exit_tree() -> void:
	_release_player()


func _play_anim(anim_name: StringName, loop: bool) -> void:
	print("[HELL_HAND_DEBUG] _play_anim: name=%s loop=%s spine=%s pos=%s" % [anim_name, loop, _spine != null, global_position])
	if _spine == null:
		return
	var anim_state: Object = null
	if _spine.has_method("get_animation_state"):
		anim_state = _spine.get_animation_state()
	elif _spine.has_method("getAnimationState"):
		anim_state = _spine.getAnimationState()
	if anim_state == null:
		print("[HELL_HAND_DEBUG] _play_anim: anim_state is NULL, cannot play %s" % anim_name)
		return
	print("[HELL_HAND_DEBUG] _play_anim: anim_state found, has set_animation=%s has setAnimation=%s" % [anim_state.has_method("set_animation"), anim_state.has_method("setAnimation")])
	if anim_state.has_method("set_animation"):
		anim_state.set_animation(String(anim_name), loop, 0)
	elif anim_state.has_method("setAnimation"):
		anim_state.setAnimation(String(anim_name), loop, 0)


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
