extends ActionLeaf
class_name ActGhostTug
func tick(actor: Node, blackboard: Blackboard) -> int:
	var b := actor as BossGhostWitch
	return FAILURE if b == null else b.bt_act_ghost_tug(blackboard)
