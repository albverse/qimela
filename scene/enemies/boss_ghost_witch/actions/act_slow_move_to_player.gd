extends ActionLeaf

func tick(actor: Node, _blackboard: Blackboard) -> int:
	var boss := actor as BossGhostWitch
	if boss == null:
		return FAILURE
	boss.bt_move_toward_player(boss.slow_move_speed, &"phase1/walk")
	return RUNNING
