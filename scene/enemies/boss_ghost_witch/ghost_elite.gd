extends Node2D
class_name GhostElite

signal elite_destroyed

func apply_hit(_hit) -> bool:
	elite_destroyed.emit()
	queue_free()
	return true
