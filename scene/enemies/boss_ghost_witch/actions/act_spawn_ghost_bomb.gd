extends ActionLeaf
class_name ActSpawnGhostBomb

## 被动技能：生成自爆幽灵（立即完成）

func tick(actor: Node, blackboard: Blackboard) -> int:
	var boss: BossGhostWitch = actor as BossGhostWitch
	if boss == null:
		return FAILURE
	var bomb: Node2D = (boss._ghost_bomb_scene as PackedScene).instantiate()
	bomb.add_to_group("ghost_bomb")
	if bomb.has_method("setup"):
		var player: Node2D = boss.get_priority_attack_target()
		bomb.call("setup", player, boss.ghost_bomb_light_energy)
	bomb.global_position = boss.global_position
	boss.get_parent().add_child(bomb)
	_set_cooldown(actor, blackboard, "cd_bomb", boss.ghost_bomb_interval)
	return SUCCESS

func _set_cooldown(actor: Node, bb: Blackboard, key: String, cd: float) -> void:
	bb.set_value(key, Time.get_ticks_msec() + cd * 1000.0, str(actor.get_instance_id()))
