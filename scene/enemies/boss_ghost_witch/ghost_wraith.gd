extends Area2D
class_name GhostWraith
@export var life_sec: float = 5.0
@export var wraith_type: int = 1
func _ready() -> void:
	add_to_group("ghost_wraith")
	await get_tree().create_timer(life_sec).timeout
	queue_free()
