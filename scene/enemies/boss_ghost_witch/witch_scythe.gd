extends Node2D
class_name WitchScythe

@export var speed: float = 360.0
var _target: Node2D = null
var _boss: BossGhostWitch = null
var _time_left: float = 3.0

func setup(player: Node2D, boss: BossGhostWitch) -> void:
	_target = player
	_boss = boss

func _physics_process(dt: float) -> void:
	_time_left -= dt
	if _target and is_instance_valid(_target):
		global_position += (_target.global_position - global_position).normalized() * speed * dt
	if _time_left <= 0.0 and _boss and is_instance_valid(_boss):
		_boss.set_meta("scythe_returned", true)
		queue_free()
