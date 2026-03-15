extends MonsterBase
class_name GhostWraith

@export var speed: float = 120.0
@export var lifetime: float = 10.0
var _t: float = 0.0
var _dir: Vector2 = Vector2.RIGHT

func _ready() -> void:
	species_id = &"ghost_wraith"
	has_hp = false
	super._ready()
	add_to_group("ghost_wraith")

func setup(direction: Vector2) -> void:
	_dir = direction.normalized()

func _physics_process(dt: float) -> void:
	_t += dt
	global_position += _dir * speed * dt
	if _t >= lifetime:
		queue_free()

func apply_hit(hit: HitData) -> bool:
	if hit != null and hit.weapon_id == &"ghost_fist":
		queue_free()
		return true
	return false
