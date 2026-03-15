extends ActionLeaf
class_name ActSummonGhosts
func tick(actor: Node, blackboard: Blackboard) -> int:
	var b := actor as BossGhostWitch
	return FAILURE if b == null else b.bt_act_summon_ghosts(blackboard)
