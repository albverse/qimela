## 检测到玩家被禁锢 → 跑到玩家位置 → 穿过 200px → 经过时斩击
extends ActionLeaf
class_name ActRunSlash

enum Step { RUN_TO, SLASH_THROUGH, DONE }
var _step: int = Step.RUN_TO
var _target_x: float = 0.0
var _overshoot_x: float = 0.0
var _run_dir: float = 1.0
var _slashed: bool = false

func before_run(actor: Node, _bb: Blackboard) -> void:
	_step = Step.RUN_TO
	_slashed = false

func tick(actor: Node, _bb: Blackboard) -> int:
	var boss := actor as BossGhostWitch
	if boss == null:
		return FAILURE

	match _step:
		Step.RUN_TO:
			var player := boss.get_priority_attack_target()
			if player == null:
				return FAILURE
			_target_x = player.global_position.x
			_run_dir = signf(_target_x - actor.global_position.x)
			if _run_dir == 0.0:
				_run_dir = 1.0
			_overshoot_x = _target_x + _run_dir * boss.p3_run_slash_overshoot_px
			boss.face_toward(player)
			boss.anim_play(&"phase3/run_slash", true)
			_step = Step.SLASH_THROUGH
			return RUNNING

		Step.SLASH_THROUGH:
			actor.velocity.x = _run_dir * boss.p3_run_speed
			if not _slashed:
				var player := boss.get_priority_attack_target()
				if player != null:
					var passed := (_run_dir > 0 and actor.global_position.x >= _target_x) \
								or (_run_dir < 0 and actor.global_position.x <= _target_x)
					if passed:
						if player.has_method("apply_damage"):
							player.call("apply_damage", 1, actor.global_position)
						_slashed = true
						boss._player_imprisoned = false
						if boss._hell_hand_instance and is_instance_valid(boss._hell_hand_instance):
							boss._hell_hand_instance.queue_free()
			var reached := (_run_dir > 0 and actor.global_position.x >= _overshoot_x) \
						  or (_run_dir < 0 and actor.global_position.x <= _overshoot_x)
			if reached or actor.is_on_wall():
				actor.velocity.x = 0.0
				boss.anim_play(&"phase3/idle", true)
				return SUCCESS
			return RUNNING
	return FAILURE

func interrupt(actor: Node, blackboard: Blackboard) -> void:
	actor.velocity.x = 0.0
	_step = Step.RUN_TO
	super(actor, blackboard)
