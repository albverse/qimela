extends ActionLeaf
class_name ActPhase3Loop

func tick(actor: Node, _blackboard: Blackboard) -> int:
	var boss := actor as BossGhostWitch
	if boss == null:
		return FAILURE
	return boss.tick_phase3_combat(get_physics_process_delta_time())
