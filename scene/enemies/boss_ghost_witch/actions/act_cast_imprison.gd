## 在玩家位置召唤地狱之手 → 0.5s 逃跑窗口 → 未逃则僵直3秒
extends ActionLeaf
class_name ActCastImprison

enum Step { CAST_ANIM, WAIT_CAST, MONITOR, DONE }
var _step: int = Step.CAST_ANIM
var _wait_cast_frames: int = 0
var _last_diag_time: float = 0.0

func before_run(actor: Node, _bb: Blackboard) -> void:
	_step = Step.CAST_ANIM
	_wait_cast_frames = 0
	print("[ACT_IMPRISON_DEBUG] before_run: starting imprison sequence")

func tick(actor: Node, blackboard: Blackboard) -> int:
	var boss := actor as BossGhostWitch
	if boss == null:
		return FAILURE
	actor.velocity.x = 0.0

	match _step:
		Step.CAST_ANIM:
			boss.anim_play(&"phase3/imprison", false)
			_step = Step.WAIT_CAST
			_wait_cast_frames = 0
			print("[ACT_IMPRISON_DEBUG] CAST_ANIM → WAIT_CAST: playing phase3/imprison")
			return RUNNING
		Step.WAIT_CAST:
			_wait_cast_frames += 1
			var now_ms: float = Time.get_ticks_msec()
			# 每2秒输出诊断日志
			if now_ms - _last_diag_time > 2000.0:
				_last_diag_time = now_ms
				print("[ACT_IMPRISON_DEBUG] WAIT_CAST: frames=%d, _current_anim=%s, _current_anim_finished=%s, anim_is_finished('phase3/imprison')=%s" % [
					_wait_cast_frames,
					boss._current_anim,
					boss._current_anim_finished,
					boss.anim_is_finished(&"phase3/imprison")
				])
			if boss.anim_is_finished(&"phase3/imprison"):
				print("[ACT_IMPRISON_DEBUG] WAIT_CAST → MONITOR: imprison anim finished after %d frames" % _wait_cast_frames)
				_spawn_hell_hand(boss)
				_step = Step.MONITOR
			return RUNNING
		Step.MONITOR:
			if boss._hell_hand_instance == null or not is_instance_valid(boss._hell_hand_instance):
				_set_cooldown(actor, blackboard, "cd_imprison", boss.p3_imprison_cooldown)
				print("[ACT_IMPRISON_DEBUG] MONITOR → SUCCESS: hell hand gone, cd set")
				return SUCCESS
			# 每 60 帧输出 MONITOR 诊断
			if Engine.get_physics_frames() % 60 == 0:
				var hand := boss._hell_hand_instance
				var hand_state := -1
				var hand_captured := false
				var hand_anim := &""
				if hand != null and is_instance_valid(hand):
					if "_state" in hand:
						hand_state = int(hand._state)
					if "_player_captured" in hand:
						hand_captured = bool(hand._player_captured)
					if "_current_anim_name" in hand:
						hand_anim = StringName(hand._current_anim_name)
				print("[ACT_IMPRISON_DEBUG] MONITOR: hell_hand valid=%s state=%d captured=%s anim=%s" % [is_instance_valid(hand), hand_state, hand_captured, hand_anim])
			return RUNNING
	return FAILURE

func _spawn_hell_hand(boss: BossGhostWitch) -> void:
	var player := boss.get_priority_attack_target()
	if player == null:
		print("[ACT_IMPRISON_DEBUG] _spawn_hell_hand: no player target, aborting")
		return
	var hand: Node2D = boss._hell_hand_scene.instantiate()
	hand.add_to_group("hell_hand")
	if hand.has_method("setup"):
		hand.call("setup", player, boss, boss.p3_imprison_stun_time)
	hand.global_position = player.global_position
	var parent := boss.get_parent()
	parent.add_child(hand)
	boss._hell_hand_instance = hand
	print("[ACT_IMPRISON_DEBUG] _spawn_hell_hand: spawned at pos=%s player_pos=%s parent=%s hand=%s" % [hand.global_position, player.global_position, parent.name, hand])

func _set_cooldown(actor: Node, bb: Blackboard, key: String, cd: float) -> void:
	bb.set_value(key, Time.get_ticks_msec() + cd * 1000.0, str(actor.get_instance_id()))

func interrupt(actor: Node, blackboard: Blackboard) -> void:
	print("[ACT_IMPRISON_DEBUG] interrupt: step=%d" % _step)
	# 如果被中断时 HellHand 还在，清理它
	var boss := actor as BossGhostWitch
	if boss != null and boss._hell_hand_instance != null and is_instance_valid(boss._hell_hand_instance):
		print("[ACT_IMPRISON_DEBUG] interrupt: cleaning up hell_hand_instance")
		boss._hell_hand_instance.queue_free()
		boss._hell_hand_instance = null
	_step = Step.CAST_ANIM
	super(actor, blackboard)
