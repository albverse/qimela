extends Node2D
class_name GhostElite

## 精英亡灵：HP=1，被 ghostfist 击杀时扣 Boss 血
## 向玩家移动，检测到近身时发动挥击（cd=1s）
## Spine 事件控制 AttackArea 启闭

var _player: Node2D = null
var _boss: Node2D = null
var _dying: bool = false
var _attacking: bool = false
var _attack_cd_end: float = 0.0
var _move_speed: float = 80.0
var _detect_range: float = 100.0
var _current_anim: StringName = &""
var _current_anim_finished: bool = false
var _current_anim_loop: bool = false

func setup(player: Node2D, boss: Node2D) -> void:
	_player = player
	_boss = boss

func _ready() -> void:
	add_to_group("ghost_elite")
	_play_anim(&"move", true)

	var hit_area: Area2D = get_node_or_null("HitArea")
	if hit_area:
		hit_area.area_entered.connect(_on_hit_by_ghostfist)

	var attack_area: Area2D = get_node_or_null("AttackArea")
	if attack_area:
		_set_area_enabled(attack_area, false)

	var spine: Node = get_node_or_null("SpineSprite")
	if spine and spine.has_signal("animation_completed"):
		spine.animation_completed.connect(_on_anim_completed_raw)
	if spine and spine.has_signal("animation_event"):
		spine.animation_event.connect(_on_spine_event)

func _on_anim_completed_raw(_ss: Variant, _te: Variant) -> void:
	_current_anim_finished = true
	if _dying:
		if _boss and is_instance_valid(_boss) and _boss.has_method("apply_real_damage"):
			_boss.call("apply_real_damage", 1)
		queue_free()
		return
	if _attacking:
		_attacking = false
		_attack_cd_end = Time.get_ticks_msec() + 1000.0
		_play_anim(&"move", true)

func _on_spine_event(a1: Variant, a2: Variant, a3: Variant, a4: Variant) -> void:
	var event_name: StringName = _extract_event_name(a1, a2, a3, a4)
	var attack_area: Area2D = get_node_or_null("AttackArea")
	match event_name:
		&"attack_hitbox_on":
			if attack_area:
				_set_area_enabled(attack_area, true)
				for body: Node2D in attack_area.get_overlapping_bodies():
					if body.is_in_group("player") and body.has_method("apply_damage"):
						body.call("apply_damage", 1, global_position)
		&"attack_hitbox_off":
			if attack_area:
				_set_area_enabled(attack_area, false)

func _physics_process(dt: float) -> void:
	if _dying or _attacking:
		return
	if _player == null or not is_instance_valid(_player):
		return

	var h_dist: float = abs(global_position.x - _player.global_position.x)

	if h_dist <= _detect_range and Time.get_ticks_msec() >= _attack_cd_end:
		_attacking = true
		_play_anim(&"attack", false)
		return

	var dir: float = signf(_player.global_position.x - global_position.x)
	global_position.x += dir * _move_speed * dt
	_play_anim(&"move", true)

func _on_hit_by_ghostfist(area: Area2D) -> void:
	if _dying:
		return
	if not area.is_in_group("ghost_fist_hitbox"):
		return
	_dying = true
	set_physics_process(false)
	var attack_area: Area2D = get_node_or_null("AttackArea")
	if attack_area:
		_set_area_enabled(attack_area, false)
	_play_anim(&"death", false)

func _set_area_enabled(area: Area2D, enabled: bool) -> void:
	area.set_deferred("monitoring", enabled)
	for child: Node in area.get_children():
		if child is CollisionShape2D:
			child.set_deferred("disabled", not enabled)

func _play_anim(anim_name: StringName, loop: bool) -> void:
	if _current_anim == anim_name and not _current_anim_finished and _current_anim_loop == loop:
		return
	_current_anim = anim_name
	_current_anim_finished = false
	_current_anim_loop = loop
	var spine: Node = get_node_or_null("SpineSprite")
	if spine == null:
		return
	var anim_state: Variant = null
	if spine.has_method("get_animation_state"):
		anim_state = spine.get_animation_state()
	if anim_state and anim_state.has_method("set_animation"):
		anim_state.set_animation(anim_name, loop, 0)

func _extract_event_name(a1: Variant, a2: Variant, a3: Variant, a4: Variant) -> StringName:
	for a: Variant in [a1, a2, a3, a4]:
		if a is Object and a.has_method("get_data"):
			var data: Variant = a.get_data()
			if data != null and data.has_method("get_event_name"):
				return StringName(data.get_event_name())
	return &""
