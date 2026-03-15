extends ActionLeaf
class_name ActDashAttack
func tick(actor: Node, blackboard: Blackboard) -> int:
	var b := actor as BossGhostWitch
	return FAILURE if b == null else b.bt_act_dash_attack(blackboard)
