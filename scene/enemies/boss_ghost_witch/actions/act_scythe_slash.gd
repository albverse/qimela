extends ActionLeaf
class_name ActScytheSlash
func tick(actor: Node, blackboard: Blackboard) -> int:
	var b := actor as BossGhostWitch
	return FAILURE if b == null else b.bt_act_scythe_slash(blackboard)
