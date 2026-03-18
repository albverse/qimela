## 检测到玩家被 HellHand 禁锢 → 1秒内跑到玩家位置 → 动画未完则继续前进 → 动画完成后结束
## run_slash 动画为非循环，播放期间移动，经过玩家时造成伤害并释放 HellHand
extends ActionLeaf
class_name ActRunSlash

enum Step { START, RUNNING, WAIT_ANIM }
var _step: int = Step.START
var _target_x: float = 0.0
var _run_dir: float = 1.0
var _run_speed: float = 0.0
var _slashed: bool = false

func before_run(actor: Node, _bb: Blackboard) -> void:
	_step = Step.START
	_slashed = false

func tick(actor: Node, _bb: Blackboard) -> int:
	var boss := actor as BossGhostWitch
	if boss == null:
		return FAILURE

	match _step:
		Step.START:
			var player := boss.get_priority_attack_target()
			if player == null:
				return FAILURE
			_target_x = player.global_position.x
			_run_dir = signf(_target_x - actor.global_position.x)
			if _run_dir == 0.0:
				_run_dir = 1.0
			# 速度 = 距离 / 1秒，至少 p3_run_speed
			var dist: float = absf(_target_x - actor.global_position.x)
			_run_speed = maxf(dist / 1.0, boss.p3_run_speed)
			boss.face_toward(player)
			boss.anim_play(&"phase3/run_slash", false)
			_step = Step.RUNNING
			print("[RUN_SLASH] START: target_x=%.0f dist=%.0f speed=%.0f dir=%.0f" % [_target_x, dist, _run_speed, _run_dir])
			return RUNNING

		Step.RUNNING:
			actor.velocity.x = _run_dir * _run_speed
			# 经过玩家位置时造成伤害并释放 HellHand
			if not _slashed:
				var passed: bool = (_run_dir > 0 and actor.global_position.x >= _target_x) \
							or (_run_dir < 0 and actor.global_position.x <= _target_x)
				if passed:
					_do_slash(boss)
			# 已经过玩家 → 检查动画是否完成
			if _slashed:
				if boss.anim_is_finished(&"phase3/run_slash") or actor.is_on_wall():
					actor.velocity.x = 0.0
					boss.anim_play(&"phase3/idle", true)
					return SUCCESS
			# 撞墙了但还没过玩家（极端情况）→ 强制斩击并等动画
			if actor.is_on_wall():
				if not _slashed:
					_do_slash(boss)
				_step = Step.WAIT_ANIM
			return RUNNING

		Step.WAIT_ANIM:
			# 撞墙停下，等动画播完
			actor.velocity.x = 0.0
			if boss.anim_is_finished(&"phase3/run_slash"):
				boss.anim_play(&"phase3/idle", true)
				return SUCCESS
			return RUNNING
	return FAILURE


func _do_slash(boss: BossGhostWitch) -> void:
	_slashed = true
	var player := boss.get_priority_attack_target()
	if player != null and player.has_method("apply_damage"):
		player.call("apply_damage", 1, boss.global_position)
	# 释放 HellHand（调用 force_release 让 HellHand 正常走 CLOSING 流程）
	if boss._hell_hand_instance != null and is_instance_valid(boss._hell_hand_instance):
		if boss._hell_hand_instance.has_method("force_release"):
			boss._hell_hand_instance.call("force_release")
		else:
			boss._hell_hand_instance.queue_free()
	boss._player_imprisoned = false
	print("[RUN_SLASH] slash: hit player, released hell_hand")


func interrupt(actor: Node, blackboard: Blackboard) -> void:
	actor.velocity.x = 0.0
	_step = Step.START
	super(actor, blackboard)
