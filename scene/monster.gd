extends CharacterBody2D

@export var max_hp: int = 3
@export var is_weakened := false

var hp: int = 0

func _ready() -> void:
	hp = max_hp
	_update_weakened_state()


func on_chain_hit(_hit_pos: Vector2, _chain_owner: Node) -> Dictionary:
	if hp <= 1:
		return {"action": "link", "target": self}

	hp = max(hp - 1, 1)
	_update_weakened_state()
	return {"action": "dissolve"}


func _update_weakened_state() -> void:
	is_weakened = (hp <= 1)
