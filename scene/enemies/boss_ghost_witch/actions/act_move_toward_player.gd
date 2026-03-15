extends ActionLeaf
class_name ActMoveTowardPlayer
func tick(actor: Node, blackboard: Blackboard) -> int:
	var b := actor as BossGhostWitch
	return FAILURE if b == null else b.bt_act_move_toward_player(blackboard)
