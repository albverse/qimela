extends MonsterBase
class_name GhostElite

var _boss: BossGhostWitch

func _ready() -> void:
	species_id = &"ghost_elite"
	has_hp = true
	max_hp = 1
	hp = 1
	super._ready()
	add_to_group("ghost_elite")

func setup(boss: BossGhostWitch) -> void:
	_boss = boss

func apply_hit(hit: HitData) -> bool:
	if hit == null or hit.weapon_id != &"ghost_fist":
		return false
	if _boss != null and is_instance_valid(_boss):
		_boss.apply_real_damage(1)
	queue_free()
	return true
