extends MonsterBase
class_name GhostBomb

@export var move_speed: float = 80.0
@export var explode_delay: float = 1.0
var _target: Node2D = null
var _touch_time: float = 0.0

func _ready() -> void:
	species_id = &"ghost_bomb"
	has_hp = false
	super._ready()
	add_to_group("ghost_bomb")

func setup(target: Node2D) -> void:
	_target = target

func _physics_process(dt: float) -> void:
	if _target == null:
		return
	var dir := (_target.global_position - global_position).normalized()
	global_position += dir * move_speed * dt
	if global_position.distance_to(_target.global_position) < 30.0:
		_touch_time += dt
		if _touch_time >= explode_delay:
			if _target.has_method("apply_damage"):
				_target.call("apply_damage", 1, global_position)
			if EventBus:
				EventBus.healing_burst.emit(5.0)
			queue_free()

func apply_hit(hit: HitData) -> bool:
	if hit != null and hit.weapon_id == &"ghost_fist":
		queue_free()
		return true
	return false
