## Phase 1 兜底：缓慢向玩家移动
extends ActionLeaf
class_name ActSlowMoveToPlayer

func tick(actor: Node, _blackboard: Blackboard) -> int:
	var boss := actor as BossGhostWitch
	if boss == null:
		return FAILURE
	var player := boss.get_priority_attack_target()
	if player == null:
		actor.velocity.x = 0.0
		boss.anim_play(&"phase1/idle", true)
		return RUNNING

	var h_dist: float = absf(player.global_position.x - actor.global_position.x)
	if h_dist < 20.0:
		actor.velocity.x = 0.0
		boss.anim_play(&"phase1/idle", true)
	else:
		var dir := signf(player.global_position.x - actor.global_position.x)
		actor.velocity.x = dir * boss.slow_move_speed
		boss.face_toward(player)
		boss.anim_play(&"phase1/walk", true)
	return RUNNING  # 永远 RUNNING，让 SelectorReactive 重评估

func interrupt(actor: Node, blackboard: Blackboard) -> void:
	if actor != null:
		actor.velocity.x = 0.0
	super(actor, blackboard)
