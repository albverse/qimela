extends MonsterBase
class_name GhostSummon

@export var lifetime: float = 3.0
var _t: float = 0.0

func _ready() -> void:
	species_id = &"ghost_summon"
	has_hp = false
	super._ready()
	add_to_group("ghost_summon")

func _physics_process(dt: float) -> void:
	_t += dt
	if _t >= lifetime:
		queue_free()
	for p in get_tree().get_nodes_in_group("player"):
		if p is Node2D and global_position.distance_to(p.global_position) < 28.0 and p.has_method("apply_damage"):
			p.call("apply_damage", 1, global_position)
