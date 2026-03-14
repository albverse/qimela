extends ActionLeaf
class_name ActSlowMoveToPlayer

func tick(actor: Node, _bb: Blackboard) -> int:
	var boss := actor as BossGhostWitch
	if boss == null:
		return FAILURE
	var player := boss.get_priority_attack_target()
	if player == null:
		boss.velocity.x = 0.0
		return RUNNING
	var h_dist := absf(player.global_position.x - boss.global_position.x)
	if h_dist < 20.0:
		boss.velocity.x = 0.0
		boss.anim_play(&"phase1/idle", true)
	else:
		var dir := signf(player.global_position.x - boss.global_position.x)
		boss.velocity.x = dir * boss.slow_move_speed
		boss.face_toward(player)
		boss.anim_play(&"phase1/walk", true)
	return RUNNING
