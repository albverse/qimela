extends ActionLeaf
class_name ActStartBattle

func tick(actor: Node, _blackboard: Blackboard) -> int:
	var boss := actor as BossGhostWitch
	if boss == null:
		return FAILURE
	return boss.tick_start_battle()
