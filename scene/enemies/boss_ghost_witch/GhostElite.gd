extends MonsterBase
class_name GhostElite

@export var move_speed: float = 80.0
@export var detect_range: float = 100.0
@export var attack_cooldown: float = 1.0

var _boss: BossGhostWitch = null
var _player: Node2D = null
var _dying: bool = false
var _attacking: bool = false
var _attack_cd_end: float = 0.0

var _spine: Node = null
var _attack_area: Area2D = null
var _current_anim: StringName = &""

func _ready() -> void:
	species_id = &"ghost_elite"
	has_hp = true
	max_hp = 1
	hp = 1
	super._ready()
	add_to_group("ghost_elite")

	_spine = get_node_or_null("SpineSprite")
	_attack_area = get_node_or_null("AttackArea")
	if _attack_area != null:
		_attack_area.monitoring = false
		_attack_area.monitorable = false

	if _spine != null:
		if _spine.has_signal("animation_event"):
			_spine.animation_event.connect(_on_spine_event)
		if _spine.has_signal("animation_completed"):
			_spine.animation_completed.connect(_on_anim_completed_raw)

	_play_anim(&"move", true)


func setup(player: Node2D, boss: BossGhostWitch) -> void:
	_player = player
	_boss = boss


func _physics_process(dt: float) -> void:
	if _attack_area != null and _attack_area.monitoring:
		for body in _attack_area.get_overlapping_bodies():
			if body != null and body.is_in_group("player") and body.has_method("apply_damage"):
				body.call("apply_damage", 1, global_position)

	if _dying or _attacking:
		return
	if _player == null or not is_instance_valid(_player):
		return

	var h_dist := absf(global_position.x - _player.global_position.x)
	if h_dist <= detect_range and Time.get_ticks_msec() >= _attack_cd_end:
		_attacking = true
		_play_anim(&"attack", false)
		return

	var dir := signf(_player.global_position.x - global_position.x)
	if dir == 0.0:
		dir = 1.0
	global_position.x += dir * move_speed * dt
	_play_anim(&"move", true)


func apply_hit(hit: HitData) -> bool:
	if _dying:
		return false
	if hit == null or hit.weapon_id != &"ghost_fist":
		return false
	_dying = true
	_attacking = false
	if _attack_area != null:
		_attack_area.monitoring = false
		_attack_area.monitorable = false
	_play_anim(&"death", false)
	print("[GHOST_ELITE_DEBUG] hit by ghostfist, playing death anim")
	return true


func _on_spine_event(a1 = null, a2 = null, a3 = null, a4 = null) -> void:
	var e := _extract_spine_event_name(a1, a2, a3, a4)
	match e:
		&"attack_hitbox_on":
			if _attack_area != null:
				_attack_area.monitoring = true
				_attack_area.monitorable = true
		&"attack_hitbox_off":
			if _attack_area != null:
				_attack_area.monitoring = false
				_attack_area.monitorable = false


func _on_anim_completed_raw(a1 = null, a2 = null, a3 = null) -> void:
	var anim_name := _extract_completed_anim_name(a1, a2, a3)
	if anim_name == &"attack":
		_attacking = false
		_attack_cd_end = Time.get_ticks_msec() + attack_cooldown * 1000.0
		_play_anim(&"move", true)
	elif anim_name == &"death":
		if _boss != null and is_instance_valid(_boss):
			print("[GHOST_ELITE_DEBUG] death anim finished, calling boss.apply_real_damage(1), boss.hp=%d" % _boss.hp)
			_boss.apply_real_damage(1)
		queue_free()


func _play_anim(anim_name: StringName, loop: bool) -> void:
	if _spine == null:
		return
	if _current_anim == anim_name:
		return
	_current_anim = anim_name
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
