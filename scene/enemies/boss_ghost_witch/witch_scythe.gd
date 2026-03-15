extends Node2D
class_name WitchScythe

@export var fly_speed: float = 500.0
var owner_boss: BossGhostWitch = null
var return_to_owner: bool = false

func _physics_process(dt: float) -> void:
	if owner_boss == null or not return_to_owner:
		return
	global_position = global_position.move_toward(owner_boss.global_position, fly_speed * dt)
	if global_position.distance_to(owner_boss.global_position) < 12.0:
		owner_boss._scythe_in_hand = true
		queue_free()
