extends ActionLeaf
class_name ActP3MoveTowardPlayer
func tick(actor: Node, blackboard: Blackboard) -> int:
	var b := actor as BossGhostWitch
	return FAILURE if b == null else b.bt_act_p3_move_toward_player(blackboard)
