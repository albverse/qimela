extends ActionLeaf
class_name ActP3MoveTowardPlayer

## Phase 3 移动兜底

func tick(actor: Node, _bb: Blackboard) -> int:
	var boss: BossGhostWitch = actor as BossGhostWitch
	if boss == null:
		return FAILURE
	if not boss._scythe_in_hand:
		actor.velocity.x = 0.0
		boss.anim_play(&"phase3/idle_no_scythe", true)
		return RUNNING
	var player: Node2D = boss.get_priority_attack_target()
	if player == null:
		actor.velocity.x = 0.0
		boss.anim_play(&"phase3/idle", true)
		return RUNNING
	var h_dist: float = abs(player.global_position.x - actor.global_position.x)
	if h_dist < 30.0:
		actor.velocity.x = 0.0
		boss.anim_play(&"phase3/idle", true)
	else:
		var dir: float = signf(player.global_position.x - actor.global_position.x)
		actor.velocity.x = dir * boss.p3_move_speed
		boss.face_toward(player)
		boss.anim_play(&"phase3/walk", true)
	return RUNNING
