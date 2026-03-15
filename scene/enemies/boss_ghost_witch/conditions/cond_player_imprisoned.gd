extends ConditionLeaf
class_name CondPlayerImprisoned
func tick(actor: Node, _bb: Blackboard) -> int:
	var boss := actor as BossGhostWitch
	return SUCCESS if boss != null and boss._player_imprisoned else FAILURE
