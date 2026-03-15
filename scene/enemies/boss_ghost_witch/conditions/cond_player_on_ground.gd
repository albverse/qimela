extends ConditionLeaf
class_name CondPlayerOnGround
func tick(actor: Node, _bb: Blackboard) -> int:
	var boss := actor as BossGhostWitch
	if boss == null:
		return FAILURE
	return SUCCESS if boss.is_player_on_ground() else FAILURE
