extends Node2D
class_name GhostElite

@export var speed: float = 90.0

var _player: Node2D = null
var _boss: BossGhostWitch = null
var _attack_cd_end_ms: float = 0.0

func setup(player: Node2D, boss: BossGhostWitch) -> void:
	_player = player
	_boss = boss

func _ready() -> void:
	$HitArea.area_entered.connect(_on_hit_area_entered)

func _physics_process(dt: float) -> void:
	if _player and is_instance_valid(_player):
		global_position.x += signf(_player.global_position.x - global_position.x) * speed * dt
	if Time.get_ticks_msec() >= _attack_cd_end_ms:
		for b in $AttackArea.get_overlapping_bodies():
			if b.is_in_group("player") and b.has_method("apply_damage"):
				b.call("apply_damage", 1, global_position)
				_attack_cd_end_ms = Time.get_ticks_msec() + 1000.0

func _on_hit_area_entered(area: Area2D) -> void:
	if not area.is_in_group("ghost_fist_hitbox"):
		return
	if _boss and is_instance_valid(_boss):
		_boss.apply_real_damage(1)
	queue_free()
