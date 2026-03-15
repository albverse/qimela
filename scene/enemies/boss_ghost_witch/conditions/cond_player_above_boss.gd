extends ConditionLeaf
class_name CondPlayerAboveBoss
func tick(actor: Node, _bb: Blackboard) -> int:
	var boss := actor as BossGhostWitch
	if boss == null:
		return FAILURE
	return SUCCESS if boss.is_player_above_boss() else FAILURE
