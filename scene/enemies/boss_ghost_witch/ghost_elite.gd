extends Node2D
class_name GhostElite

@export var speed: float = 130.0
var _player: Node2D = null
var _boss: BossGhostWitch = null
var _life: float = 10.0

func setup(player: Node2D, boss: BossGhostWitch) -> void:
	_player = player
	_boss = boss

func _physics_process(dt: float) -> void:
	_life -= dt
	if _player and is_instance_valid(_player):
		global_position += (_player.global_position - global_position).normalized() * speed * dt
	if _life <= 0.0:
		queue_free()

func apply_hit(hit: HitData) -> bool:
	if hit and hit.weapon_id == &"ghost_fist":
		if _boss and is_instance_valid(_boss):
			_boss.apply_real_damage(1)
		queue_free()
		return true
	return false
