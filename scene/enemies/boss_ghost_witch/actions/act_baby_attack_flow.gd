extends ActionLeaf
class_name ActBabyAttackFlow
func tick(actor: Node, blackboard: Blackboard) -> int:
	var b := actor as BossGhostWitch
	return FAILURE if b == null else b.bt_act_baby_attack_flow(blackboard)
