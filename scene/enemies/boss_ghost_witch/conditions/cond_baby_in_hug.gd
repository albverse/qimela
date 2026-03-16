extends ConditionLeaf

func tick(actor: Node, _blackboard: Blackboard) -> int:
	var boss := actor as BossGhostWitch
	if boss == null:
		return FAILURE
	return SUCCESS if boss.is_baby_in_hug() else FAILURE
