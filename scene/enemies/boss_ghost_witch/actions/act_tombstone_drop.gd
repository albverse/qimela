extends ActionLeaf
class_name ActTombstoneDrop
func tick(actor: Node, blackboard: Blackboard) -> int:
	var b := actor as BossGhostWitch
	return FAILURE if b == null else b.bt_act_tombstone_drop(blackboard)
