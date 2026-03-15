extends ActionLeaf
class_name ActP3IdleNoScythe
func tick(actor: Node, blackboard: Blackboard) -> int:
	var b := actor as BossGhostWitch
	return FAILURE if b == null else b.bt_act_p3_idle_no_scythe(blackboard)
