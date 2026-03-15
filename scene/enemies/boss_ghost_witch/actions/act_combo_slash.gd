extends ActionLeaf
class_name ActComboSlash
func tick(actor: Node, blackboard: Blackboard) -> int:
	var b := actor as BossGhostWitch
	return FAILURE if b == null else b.bt_act_combo_slash(blackboard)
