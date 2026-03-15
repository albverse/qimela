extends ActionLeaf
class_name ActWaitTransition
func tick(actor: Node, blackboard: Blackboard) -> int:
	var b := actor as BossGhostWitch
	return FAILURE if b == null else b.bt_wait_transition(blackboard)
