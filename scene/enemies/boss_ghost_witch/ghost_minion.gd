extends Node2D
class_name GhostMinion

@export var life_time: float = 8.0

func _ready() -> void:
	if life_time > 0.0:
		await get_tree().create_timer(life_time).timeout
		if is_inside_tree():
			queue_free()

func apply_hit(hit: HitData) -> bool:
	if hit == null:
		return false
	if hit.weapon_id != &"ghost_fist":
		return false
	queue_free()
	return true
