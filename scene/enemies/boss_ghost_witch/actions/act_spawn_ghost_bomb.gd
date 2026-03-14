extends ActionLeaf
class_name ActSpawnGhostBomb

func tick(actor: Node, blackboard: Blackboard) -> int:
	var boss := actor as BossGhostWitch
	if boss == null:
		return FAILURE
	var bomb := boss._ghost_bomb_scene.instantiate()
	bomb.add_to_group("ghost_bomb")
	if bomb.has_method("setup"):
		bomb.call("setup", boss.get_priority_attack_target(), boss.ghost_bomb_light_energy)
	bomb.global_position = boss.global_position
	boss.get_parent().add_child(bomb)
	blackboard.set_value("cd_bomb", Time.get_ticks_msec() + boss.ghost_bomb_interval * 1000.0, str(actor.get_instance_id()))
	return SUCCESS
