extends ConditionLeaf
class_name CondPlayerOnPlatform
func tick(actor: Node, _bb: Blackboard) -> int:
	var boss := actor as BossGhostWitch
	if boss == null:
		return FAILURE
	return SUCCESS if boss.is_player_on_platform() else FAILURE
