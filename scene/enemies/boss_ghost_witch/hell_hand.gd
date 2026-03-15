extends Node2D
class_name HellHand

func apply_hit(_hit) -> bool:
	queue_free()
	return true
