extends ActionLeaf

func tick(actor: Node, _blackboard: Blackboard) -> int:
	var boss := actor as BossGhostWitch
	if boss == null:
		return FAILURE
	return boss.bt_baby_attack_flow()
