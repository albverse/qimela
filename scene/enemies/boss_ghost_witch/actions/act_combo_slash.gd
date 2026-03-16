## 3秒内连续检测 attack1/attack2/attack3 区域
extends ActionLeaf
class_name ActComboSlash

enum Step { COMBO1, WAIT1, COMBO2, WAIT2, COMBO3, WAIT3, DONE }
var _step: int = Step.COMBO1

func before_run(actor: Node, _bb: Blackboard) -> void:
	_step = Step.COMBO1

func tick(actor: Node, blackboard: Blackboard) -> int:
	var boss := actor as BossGhostWitch
	if boss == null:
		return FAILURE

	match _step:
		Step.COMBO1:
			var player := boss.get_priority_attack_target()
			if player:
				boss.face_toward(player)
			boss.anim_play(&"phase3/combo1", false)
			_step = Step.WAIT1
			return RUNNING
		Step.WAIT1:
			if boss.anim_is_finished(&"phase3/combo1"):
				_step = Step.COMBO2
			return RUNNING
		Step.COMBO2:
			boss.anim_play(&"phase3/combo2", false)
			_step = Step.WAIT2
			return RUNNING
		Step.WAIT2:
			if boss.anim_is_finished(&"phase3/combo2"):
				_step = Step.COMBO3
			return RUNNING
		Step.COMBO3:
			boss.anim_play(&"phase3/combo3", false)
			_step = Step.WAIT3
			return RUNNING
		Step.WAIT3:
			if boss.anim_is_finished(&"phase3/combo3"):
				_set_cooldown(actor, blackboard, "cd_combo", boss.p3_combo_cooldown)
				return SUCCESS
			return RUNNING
	return FAILURE

func _set_cooldown(actor: Node, bb: Blackboard, key: String, cd: float) -> void:
	bb.set_value(key, Time.get_ticks_msec() + cd * 1000.0, str(actor.get_instance_id()))

func interrupt(actor: Node, blackboard: Blackboard) -> void:
	_step = Step.COMBO1
	var boss := actor as BossGhostWitch
	if boss:
		boss._close_all_combo_hitboxes()
	super(actor, blackboard)
