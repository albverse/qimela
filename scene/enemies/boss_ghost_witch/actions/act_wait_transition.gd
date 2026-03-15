extends ActionLeaf

func tick(actor: Node, _blackboard: Blackboard) -> int:
	var boss := actor as BossGhostWitch
	if boss == null:
		return FAILURE
	boss.bt_hold_transition()
	return RUNNING if boss.is_phase_transitioning() else SUCCESS
