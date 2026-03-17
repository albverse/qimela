extends MonsterBase
class_name GhostBomb

@export var move_speed: float = 60.0
@export var explode_delay: float = 1.0
@export var light_energy: float = 5.0
@export var s_curve_amplitude: float = 25.0
@export var s_curve_frequency: float = 5.0

var _target: Node2D = null
var _touch_time: float = 0.0
var _exploding: bool = false
var _appeared: bool = false
var _t: float = 0.0

var _spine: Node = null
var _explosion_area: Area2D = null
var _light_area: Area2D = null

func _ready() -> void:
	species_id = &"ghost_bomb"
	has_hp = false
	super._ready()
	add_to_group("ghost_bomb")

	_spine = get_node_or_null("SpineSprite")
	_explosion_area = get_node_or_null("ExplosionArea")
	_light_area = get_node_or_null("LightArea")
	_set_area_enabled(_explosion_area, false)
	_set_area_enabled(_light_area, false)

	if _spine != null:
		if _spine.has_signal("animation_event"):
			_spine.animation_event.connect(_on_spine_event)
		if _spine.has_signal("animation_completed"):
			_spine.animation_completed.connect(_on_anim_completed_raw)

	_play_anim(&"appear", false)
	print("[GHOST_BOMB_DEBUG] _ready: spawned at %s" % global_position)


func setup(target: Node2D, override_light_energy: float = -1.0) -> void:
	_target = target
	if override_light_energy >= 0.0:
		light_energy = override_light_energy


func _physics_process(dt: float) -> void:
	if _explosion_area != null and _explosion_area.monitoring:
		for body in _explosion_area.get_overlapping_bodies():
			if body != null and body.is_in_group("player") and body.has_method("apply_damage"):
				body.call("apply_damage", 1, global_position)

	if _exploding:
		return
	if not _appeared or _target == null or not is_instance_valid(_target):
		return

	_t += dt
	var to_target := (_target.global_position - global_position)
	var dir := to_target.normalized()
	var lateral := Vector2(-dir.y, dir.x)
	var wave := sin(_t * s_curve_frequency) * s_curve_amplitude
	global_position += (dir * move_speed + lateral * wave) * dt

	if global_position.distance_to(_target.global_position) < 30.0:
		_touch_time += dt
		if _touch_time >= explode_delay:
			_exploding = true
			_play_anim(&"explode", false)
	else:
		_touch_time = 0.0


func apply_hit(hit: HitData) -> bool:
	if hit != null and hit.weapon_id == &"ghost_fist":
		print("[GHOST_BOMB_DEBUG] destroyed by ghostfist")
		queue_free()
		return true
	return false


func _on_spine_event(a1 = null, a2 = null, a3 = null, a4 = null) -> void:
	var e := _extract_spine_event_name(a1, a2, a3, a4)
	match e:
		&"explosion_hitbox_on":
			_set_area_enabled(_explosion_area, true)
		&"explosion_hitbox_off":
			_set_area_enabled(_explosion_area, false)
		&"light_emit":
			if EventBus:
				EventBus.healing_burst.emit(light_energy)


func _on_anim_completed_raw(a1 = null, a2 = null, a3 = null) -> void:
	var anim_name := _extract_completed_anim_name(a1, a2, a3)
	if anim_name == &"appear":
		_appeared = true
		_play_anim(&"move", true)
	elif anim_name == &"explode":
		queue_free()


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


func _set_area_enabled(area: Area2D, enabled: bool) -> void:
	if area == null:
		return
	area.monitoring = enabled
	area.monitorable = enabled


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
