extends MonsterBase
class_name GhostSummon

@export var lifetime: float = 3.0
var _delay: float = 0.3
var _spawned: bool = false
var _t: float = 0.0

var _spine: Node = null
var _ghost_hit_area: Area2D = null

func setup(delay: float) -> void:
	_delay = delay


func _ready() -> void:
	species_id = &"ghost_summon"
	has_hp = false
	super._ready()
	add_to_group("ghost_summon")

	_spine = get_node_or_null("SpineSprite")
	_ghost_hit_area = get_node_or_null("GhostHitArea")
	_set_hitarea_enabled(false)
	_play_anim(&"circle_appear", false)

	if _spine != null and _spine.has_signal("animation_event"):
		_spine.animation_event.connect(_on_spine_event)


func _physics_process(dt: float) -> void:
	if not _spawned:
		_delay -= dt
		if _delay <= 0.0:
			_spawned = true
			_play_anim(&"ghost_fly_out", false)
	else:
		_t += dt
		if _t >= lifetime:
			queue_free()

	if _ghost_hit_area != null and _ghost_hit_area.monitoring:
		for p in _ghost_hit_area.get_overlapping_bodies():
			if p != null and p.is_in_group("player") and p.has_method("apply_damage"):
				p.call("apply_damage", 1, global_position)


func _on_spine_event(a1 = null, a2 = null, a3 = null, a4 = null) -> void:
	var e := _extract_spine_event_name(a1, a2, a3, a4)
	match e:
		&"ghost_hitbox_on":
			_set_hitarea_enabled(true)
		&"ghost_hitbox_off":
			_set_hitarea_enabled(false)


func _play_anim(anim_name: StringName, loop: bool) -> void:
	if _spine == null:
		return
	var anim_state: Object = null
	if _spine.has_method("get_animation_state"):
		anim_state = _spine.get_animation_state()
	elif _spine.has_method("getAnimationState"):
		anim_state = _spine.getAnimationState()
	if anim_state == null:
		return
	if anim_state.has_method("set_animation"):
		anim_state.set_animation(String(anim_name), loop, 0)
	elif anim_state.has_method("setAnimation"):
		anim_state.setAnimation(String(anim_name), loop, 0)


func _set_hitarea_enabled(enabled: bool) -> void:
	if _ghost_hit_area == null:
		return
	_ghost_hit_area.monitoring = enabled
	_ghost_hit_area.monitorable = enabled


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
