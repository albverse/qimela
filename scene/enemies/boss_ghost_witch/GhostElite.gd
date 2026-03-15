extends Area2D
class_name GhostElite

var _boss: BossGhostWitch

func _ready() -> void:
	add_to_group("ghost_elite")
	area_entered.connect(_on_area_entered)

func setup(boss: BossGhostWitch) -> void:
	_boss = boss

func _on_area_entered(area: Area2D) -> void:
	if area and area.is_in_group("ghost_fist_hitbox"):
		if _boss and _boss.has_method("apply_real_damage"):
			_boss.apply_real_damage(1)
		queue_free()
