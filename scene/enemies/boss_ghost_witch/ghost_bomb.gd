extends Area2D
class_name GhostBomb
@export var life_sec: float = 4.0
func _ready() -> void:
	add_to_group("ghost_bomb")
	await get_tree().create_timer(life_sec).timeout
	queue_free()
