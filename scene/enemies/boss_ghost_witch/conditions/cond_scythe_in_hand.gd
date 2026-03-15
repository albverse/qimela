extends ConditionLeaf
class_name CondScytheInHand
func tick(actor: Node, _bb: Blackboard) -> int:
	var boss := actor as BossGhostWitch
	return SUCCESS if boss != null and boss._scythe_in_hand else FAILURE
