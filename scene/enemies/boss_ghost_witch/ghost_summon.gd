extends Node2D
class_name GhostSummon

@export var life_sec: float = 3.0

func _ready() -> void:
	var t := get_tree().create_timer(life_sec)
	t.timeout.connect(queue_free)
