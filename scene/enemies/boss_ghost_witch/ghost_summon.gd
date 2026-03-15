extends Node2D
class_name GhostSummon

@export var rise_speed: float = 120.0
@export var life_sec: float = 2.0

func _physics_process(dt: float) -> void:
	global_position.y -= rise_speed * dt
	life_sec -= dt
	if life_sec <= 0.0:
		queue_free()
