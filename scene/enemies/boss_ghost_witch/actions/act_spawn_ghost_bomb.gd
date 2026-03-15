extends ActionLeaf
class_name ActSpawnGhostBomb
func tick(actor: Node, blackboard: Blackboard) -> int:
	var b := actor as BossGhostWitch
	return FAILURE if b == null else b.bt_act_spawn_ghost_bomb(blackboard)
