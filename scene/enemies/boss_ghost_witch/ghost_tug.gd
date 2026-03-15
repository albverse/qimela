extends Node2D
class_name GhostTug
@export var life_sec: float = 3.0
func _ready() -> void:
	add_to_group("ghost_tug")
	await get_tree().create_timer(life_sec).timeout
	queue_free()
