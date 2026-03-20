extends CharacterBody2D
class_name GhostBomb

## 自爆幽灵：S 形移动追踪玩家，触碰后延迟爆炸
## Spine 事件控制伤害区和光照区
## 被 ghostfist 打中直接消失（不播爆炸）

var _player: Node2D = null
var _light_energy: float = 5.0
var _move_speed: float = 60.0
var _track_interval: float = 2.0
var _track_timer: float = 0.0
var _target_pos: Vector2 = Vector2.ZERO
var _time: float = 0.0
var _exploding: bool = false
var _appeared: bool = false
var _current_anim: StringName = &""
var _current_anim_finished: bool = false
var _current_anim_loop: bool = false

@export var s_curve_amplitude: float = 40.0
@export var s_curve_frequency: float = 2.0
@export var explode_delay: float = 1.0

func setup(player: Node2D, light_energy: float) -> void:
	_player = player
	_light_energy = light_energy

func _ready() -> void:
	add_to_group("ghost_bomb")
	_play_anim(&"appear", false)

	var hurt_area: Area2D = get_node_or_null("HurtArea")
	if hurt_area:
		hurt_area.area_entered.connect(_on_ghostfist_hit)

	var explosion_area: Area2D = get_node_or_null("ExplosionArea")
	if explosion_area:
		explosion_area.body_entered.connect(_on_touch_player)
		_set_area_enabled(explosion_area, false)

	var spine: Node = get_node_or_null("SpineSprite")
	if spine and spine.has_signal("animation_completed"):
		spine.animation_completed.connect(_on_anim_completed_raw)
	if spine and spine.has_signal("animation_event"):
		spine.animation_event.connect(_on_spine_event)

func _on_anim_completed_raw(_ss: Variant, _te: Variant) -> void:
	_current_anim_finished = true
	if not _appeared and not _exploding:
		_appeared = true
		_update_target()
		_play_anim(&"move", true)
		return
	if _exploding:
		queue_free()

func _physics_process(dt: float) -> void:
	if _exploding or not _appeared:
		return
	_time += dt
	_track_timer += dt
	if _track_timer >= _track_interval:
		_track_timer = 0.0
		_update_target()
	var dir: Vector2 = (_target_pos - global_position).normalized()
	var s_offset: float = sin(_time * s_curve_frequency) * s_curve_amplitude
	velocity = dir * _move_speed + Vector2(s_offset, 0)
	move_and_slide()

func _on_touch_player(body: Node2D) -> void:
	if _exploding:
		return
	if not body.is_in_group("player"):
		return
	_start_explode()

func _start_explode() -> void:
	_exploding = true
	velocity = Vector2.ZERO
	await get_tree().create_timer(explode_delay).timeout
	if not is_inside_tree():
		return
	_play_anim(&"explode", false)

func _on_spine_event(a1: Variant, a2: Variant, a3: Variant, a4: Variant) -> void:
	var event_name: StringName = _extract_event_name(a1, a2, a3, a4)
	var explosion_area: Area2D = get_node_or_null("ExplosionArea")
	match event_name:
		&"explosion_hitbox_on":
			if explosion_area:
				_set_area_enabled(explosion_area, true)
				for body: Node2D in explosion_area.get_overlapping_bodies():
					if body.is_in_group("player") and body.has_method("apply_damage"):
						body.call("apply_damage", 1, global_position)
		&"explosion_hitbox_off":
			if explosion_area:
				_set_area_enabled(explosion_area, false)
		&"light_emit":
			if EventBus and EventBus.has_method("emit_healing_burst"):
				EventBus.call("emit_healing_burst", _light_energy)

func _on_ghostfist_hit(area: Area2D) -> void:
	if area.is_in_group("ghost_fist_hitbox"):
		queue_free()

func _update_target() -> void:
	if _player and is_instance_valid(_player):
		_target_pos = _player.global_position

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
