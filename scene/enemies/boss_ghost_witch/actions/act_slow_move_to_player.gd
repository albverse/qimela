extends ActionLeaf
class_name ActSlowMoveToPlayer

## Phase 1 兜底：缓慢向玩家移动

func tick(actor: Node, _blackboard: Blackboard) -> int:
	var boss: BossGhostWitch = actor as BossGhostWitch
	if boss == null:
		return FAILURE
	var player: Node2D = boss.get_priority_attack_target()
	if player == null:
		return RUNNING
	var h_dist: float = abs(player.global_position.x - actor.global_position.x)
	if h_dist < 20.0:
		actor.velocity.x = 0.0
		boss.anim_play(&"phase1/idle", true)
	else:
		var dir: float = signf(player.global_position.x - actor.global_position.x)
		actor.velocity.x = dir * boss.slow_move_speed
		boss.face_toward(player)
		boss.anim_play(&"phase1/walk", true)
	return RUNNING
