extends ActionLeaf
class_name ActSlowMoveToPlayer
func tick(actor: Node, blackboard: Blackboard) -> int:
	var b := actor as BossGhostWitch
	return FAILURE if b == null else b.bt_act_slow_move_to_player(blackboard)
