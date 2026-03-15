extends Node2D
class_name GhostTug

@export var pull_speed: float = 400.0
var target: Node2D = null

func _physics_process(dt: float) -> void:
	if target == null:
		return
	var dir := (global_position - target.global_position).normalized()
	if target.has_method("apply_external_pull"):
		target.call("apply_external_pull", dir * pull_speed * dt)
