## 蓄力 → 快速冲刺 → 刹车减速 → 结束
extends ActionLeaf
class_name ActDashAttack

enum Step { FACE_TARGET, CHARGE, DASH, BRAKE, DONE }
var _step: int = Step.FACE_TARGET
var _charge_end: float = 0.0
var _dash_dir: float = 1.0
var _dash_start_x: float = 0.0
var _dash_distance: float = 600.0
var _hit_player: bool = false

func before_run(actor: Node, _bb: Blackboard) -> void:
	_step = Step.FACE_TARGET
	_hit_player = false

func tick(actor: Node, blackboard: Blackboard) -> int:
	var boss := actor as BossGhostWitch
	if boss == null:
		return FAILURE

	match _step:
		Step.FACE_TARGET:
			var player := boss.get_priority_attack_target()
			if player == null:
				return FAILURE
			boss.face_toward(player)
			_dash_dir = signf(player.global_position.x - actor.global_position.x)
			if _dash_dir == 0.0:
				_dash_dir = 1.0
			_step = Step.CHARGE
			_charge_end = Time.get_ticks_msec() + boss.p3_dash_charge_time * 1000.0
			boss.anim_play(&"phase3/dash_charge", false)
			return RUNNING

		Step.CHARGE:
			if Time.get_ticks_msec() >= _charge_end:
				_dash_start_x = actor.global_position.x
				_step = Step.DASH
				boss.anim_play(&"phase3/dash", true)
			return RUNNING

		Step.DASH:
			actor.velocity.x = _dash_dir * boss.p3_dash_speed
			actor.velocity.y = 0.0
			if not _hit_player:
				for body in boss._scythe_detect_area.get_overlapping_bodies():
					if body.is_in_group("player") and body.has_method("apply_damage"):
						body.call("apply_damage", 1, actor.global_position)
						_hit_player = true
						break
			var traveled := abs(actor.global_position.x - _dash_start_x)
			if traveled >= _dash_distance or actor.is_on_wall():
				actor.velocity.x = 0.0
				_step = Step.BRAKE
				boss.anim_play(&"phase3/dash_brake", false)
			return RUNNING

		Step.BRAKE:
			actor.velocity.x = 0.0
			if boss.anim_is_finished(&"phase3/dash_brake"):
				_set_cooldown(actor, blackboard, "cd_dash", boss.p3_dash_cooldown)
				return SUCCESS
			return RUNNING
	return FAILURE

func _set_cooldown(actor: Node, bb: Blackboard, key: String, cd: float) -> void:
	bb.set_value(key, Time.get_ticks_msec() + cd * 1000.0, str(actor.get_instance_id()))

func interrupt(actor: Node, blackboard: Blackboard) -> void:
	actor.velocity.x = 0.0
	_step = Step.FACE_TARGET
	super(actor, blackboard)
