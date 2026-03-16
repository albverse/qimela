## Phase 3 镰刀在手时向玩家移动
extends ActionLeaf
class_name ActP3MoveTowardPlayer

func tick(actor: Node, _bb: Blackboard) -> int:
	var boss := actor as BossGhostWitch
	if boss == null:
		return FAILURE
	if not boss._scythe_in_hand:
		actor.velocity.x = 0.0
		boss.anim_play(&"phase3/idle_no_scythe", true)
		return RUNNING
	var player := boss.get_priority_attack_target()
	if player == null:
		actor.velocity.x = 0.0
		boss.anim_play(&"phase3/idle", true)
		return RUNNING
	var h_dist: float = absf(player.global_position.x - actor.global_position.x)
	if h_dist < 30.0:
		actor.velocity.x = 0.0
		boss.anim_play(&"phase3/idle", true)
	else:
		var dir := signf(player.global_position.x - actor.global_position.x)
		actor.velocity.x = dir * boss.p3_move_speed
		boss.face_toward(player)
		boss.anim_play(&"phase3/walk", true)
	return RUNNING

func interrupt(actor: Node, blackboard: Blackboard) -> void:
	if actor != null:
		actor.velocity.x = 0.0
	super(actor, blackboard)
