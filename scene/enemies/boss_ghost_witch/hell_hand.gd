extends Area2D
class_name HellHand
@export var life_sec: float = 3.0
func _ready() -> void:
	add_to_group("hell_hand")
	await get_tree().create_timer(life_sec).timeout
	queue_free()
