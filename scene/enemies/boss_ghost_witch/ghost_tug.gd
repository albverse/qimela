extends Node2D
class_name GhostTug

@export var pull_speed: float = 220.0
@export var life_sec: float = 2.0
var _player: Node2D = null
var _boss: Node2D = null

func setup(player: Node2D, boss: Node2D, speed: float) -> void:
	_player = player
	_boss = boss
	pull_speed = speed

func _physics_process(dt: float) -> void:
	if _player and is_instance_valid(_player) and _boss and is_instance_valid(_boss):
		var dir := (_boss.global_position - _player.global_position).normalized()
		_player.global_position += dir * pull_speed * dt
	life_sec -= dt
	if life_sec <= 0.0:
		queue_free()
