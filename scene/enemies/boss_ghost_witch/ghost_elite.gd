extends Area2D
class_name GhostElite
@export var hp: int = 1
func _ready() -> void:
	add_to_group("ghost_elite")
func apply_hit(hit: HitData) -> bool:
	if hit == null or hit.weapon_id != &"ghost_fist":
		return false
	hp -= max(hit.damage, 1)
	if hp <= 0:
		queue_free()
	return true
