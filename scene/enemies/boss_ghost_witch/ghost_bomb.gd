extends Node2D
class_name GhostBomb

@export var speed: float = 180.0
@export var explode_range: float = 40.0
@export var damage: int = 1
var _player: Node2D = null
var _life: float = 3.0

func setup(player: Node2D, _light_energy: float = 0.0) -> void:
	_player = player

func _physics_process(dt: float) -> void:
	_life -= dt
	if _player and is_instance_valid(_player):
		var to_target := _player.global_position - global_position
		if to_target.length() <= explode_range:
			if _player.has_method("apply_damage"):
				_player.call("apply_damage", damage, global_position)
			queue_free()
			return
		global_position += to_target.normalized() * speed * dt
	if _life <= 0.0:
		queue_free()
