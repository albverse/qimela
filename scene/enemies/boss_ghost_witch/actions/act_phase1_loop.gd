extends ActionLeaf
class_name ActPhase1Loop

func tick(actor: Node, _blackboard: Blackboard) -> int:
	var boss := actor as BossGhostWitch
	if boss == null:
		return FAILURE
	return boss.tick_phase1_combat(get_physics_process_delta_time())
