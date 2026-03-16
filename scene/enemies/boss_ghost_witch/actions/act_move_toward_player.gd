## Phase 2 移动兜底
extends ActionLeaf
class_name ActMoveTowardPlayer

@export var move_speed: float = 80.0

func tick(actor: Node, _bb: Blackboard) -> int:
	var boss := actor as BossGhostWitch
	if boss == null:
		return FAILURE
	var player := boss.get_priority_attack_target()
	if player == null:
		actor.velocity.x = 0.0
		return RUNNING

	var h_dist := abs(player.global_position.x - actor.global_position.x)
	if h_dist < 30.0:
		actor.velocity.x = 0.0
		boss.anim_play(&"phase2/idle", true)
	else:
		var dir := signf(player.global_position.x - actor.global_position.x)
		actor.velocity.x = dir * move_speed
		boss.face_toward(player)
		boss.anim_play(&"phase2/walk", true)
	return RUNNING
