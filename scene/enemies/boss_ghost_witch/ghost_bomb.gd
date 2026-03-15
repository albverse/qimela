extends Node2D
class_name GhostBomb

@export var life_sec: float = 5.0

func _ready() -> void:
	add_to_group("ghost_bomb")
	var t := get_tree().create_timer(life_sec)
	t.timeout.connect(queue_free)
