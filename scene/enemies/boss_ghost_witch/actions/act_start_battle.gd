extends ActionLeaf
class_name ActStartBattle
func tick(actor: Node, blackboard: Blackboard) -> int:
	var b := actor as BossGhostWitch
	return FAILURE if b == null else b.bt_act_start_battle(blackboard)
