extends ActionLeaf

func tick(actor: Node, blackboard: Blackboard) -> int:
	var boss := actor as BossGhostWitch
	if boss == null:
		return FAILURE
	return boss.bt_cast_phase2_skill(blackboard, "cd_tug", boss.ghost_tug_cooldown, &"phase2/ghost_tug")
