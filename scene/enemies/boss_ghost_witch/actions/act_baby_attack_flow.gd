extends ActionLeaf
class_name ActBabyAttackFlow

enum Step { EXPLODE, REPAIR, RETURN_HOME }
var _step: int = Step.EXPLODE

func before_run(_actor: Node, _bb: Blackboard) -> void:
	_step = Step.EXPLODE

func tick(actor: Node, _bb: Blackboard) -> int:
	var boss := actor as BossGhostWitch
	if boss == null:
		return FAILURE
	match _step:
		Step.EXPLODE:
			if boss.baby_state == BossGhostWitch.BabyState.EXPLODED:
				boss.baby_anim_play(&"baby/explode", false)
				if boss.baby_anim_is_finished(&"baby/explode"):
					boss.baby_state = BossGhostWitch.BabyState.REPAIRING
					_step = Step.REPAIR
		Step.REPAIR:
			boss.baby_anim_play(&"baby/repair", false)
			if boss.baby_anim_is_finished(&"baby/repair"):
				boss.baby_state = BossGhostWitch.BabyState.RETURNING
				_step = Step.RETURN_HOME
		Step.RETURN_HOME:
			boss.baby_anim_play(&"baby/return", true)
			boss._baby_statue.global_position = boss._mark_hug.global_position
			boss.baby_state = BossGhostWitch.BabyState.IN_HUG
			boss.anim_play(&"phase1/catch_baby", false)
			return SUCCESS
	return RUNNING

func interrupt(actor: Node, blackboard: Blackboard) -> void:
	_step = Step.EXPLODE
	super(actor, blackboard)
