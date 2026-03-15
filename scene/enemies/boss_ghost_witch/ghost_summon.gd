extends Area2D
class_name GhostSummon
@export var life_sec: float = 2.0
func _ready() -> void:
	add_to_group("ghost_summon")
	await get_tree().create_timer(life_sec).timeout
	queue_free()
