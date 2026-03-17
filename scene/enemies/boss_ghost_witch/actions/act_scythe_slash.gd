## Phase 2 镰刀斩
extends ActionLeaf
class_name ActScytheSlash

enum Step { PLAY, WAIT, DONE }
var _step: int = Step.PLAY
var _wait_frames: int = 0

func before_run(actor: Node, _bb: Blackboard) -> void:
	_step = Step.PLAY
	_wait_frames = 0

func tick(actor: Node, blackboard: Blackboard) -> int:
	var boss := actor as BossGhostWitch
	if boss == null:
		return FAILURE
	actor.velocity.x = 0.0

	match _step:
		Step.PLAY:
			var player := boss.get_priority_attack_target()
			if player:
				boss.face_toward(player)
			print("[ACT_SCYTHE_DEBUG] PLAY->WAIT start anim=phase2/scythe_slash boss=%s player=%s" % [boss.global_position, player.global_position if player != null else Vector2.ZERO])
			boss.anim_play(&"phase2/scythe_slash", false)
			_step = Step.WAIT
			_wait_frames = 0
			return RUNNING
		Step.WAIT:
			_wait_frames += 1
			# Spine 事件 "scythe_hitbox_on" / "scythe_hitbox_off" 驱动伤害检测
			if _wait_frames % 20 == 0:
				var player_wait := boss.get_priority_attack_target()
				var h_dist := -1.0
				if player_wait != null:
					h_dist = absf(player_wait.global_position.x - boss.global_position.x)
				print("[ACT_SCYTHE_DEBUG] WAIT frames=%d anim_finished=%s h_dist=%.2f boss=%s player=%s" % [_wait_frames, boss.anim_is_finished(&"phase2/scythe_slash"), h_dist, boss.global_position, player_wait.global_position if player_wait != null else Vector2.ZERO])
			if boss.anim_is_finished(&"phase2/scythe_slash"):
				print("[ACT_SCYTHE_DEBUG] WAIT->SUCCESS finished frames=%d" % _wait_frames)
				_set_cooldown(actor, blackboard, "cd_scythe", boss.scythe_slash_cooldown)
				return SUCCESS
			return RUNNING
	return FAILURE

func _set_cooldown(actor: Node, bb: Blackboard, key: String, cd: float) -> void:
	var actor_id := str(actor.get_instance_id())
	bb.set_value(key, Time.get_ticks_msec() + cd * 1000.0, actor_id)

func interrupt(actor: Node, blackboard: Blackboard) -> void:
	var boss := actor as BossGhostWitch
	var player := boss.get_priority_attack_target() if boss != null else null
	var h_dist := -1.0
	if boss != null and player != null:
		h_dist = absf(player.global_position.x - boss.global_position.x)
	print("[ACT_SCYTHE_DEBUG] interrupt step=%d wait_frames=%d h_dist=%.2f boss=%s player=%s" % [_step, _wait_frames, h_dist, boss.global_position if boss != null else Vector2.ZERO, player.global_position if player != null else Vector2.ZERO])
	_step = Step.PLAY
	_wait_frames = 0
	if actor != null:
		actor.velocity.x = 0.0
	super(actor, blackboard)
