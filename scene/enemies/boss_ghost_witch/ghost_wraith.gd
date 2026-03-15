extends Node2D
class_name GhostWraith

@export var speed: float = 150.0
var _player: Node2D = null
var _origin: Vector2 = Vector2.ZERO
var _type_id: int = 1
var _life: float = 5.0

func setup(type_id: int, player: Node2D, origin: Vector2) -> void:
	_type_id = type_id
	_player = player
	_origin = origin
	if _type_id == 2:
		speed = 180.0
	elif _type_id == 3:
		speed = 210.0

func _physics_process(dt: float) -> void:
	_life -= dt
	if _player and is_instance_valid(_player):
		var dir := (_player.global_position - global_position).normalized()
		global_position += dir * speed * dt
	else:
		global_position = global_position.move_toward(_origin, speed * 0.4 * dt)
	if _life <= 0.0:
		queue_free()
