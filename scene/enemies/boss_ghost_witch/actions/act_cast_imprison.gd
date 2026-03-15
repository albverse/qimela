extends ActionLeaf
class_name ActCastImprison
func tick(actor: Node, blackboard: Blackboard) -> int:
	var b := actor as BossGhostWitch
	return FAILURE if b == null else b.bt_act_cast_imprison(blackboard)
