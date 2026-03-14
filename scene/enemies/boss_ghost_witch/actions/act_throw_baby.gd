extends ActionLeaf
class_name ActThrowBaby

enum Step { ANIM_THROW, WAIT_THROW, WAIT_DONE }
var _step: int = Step.ANIM_THROW

func before_run(_actor: Node, _bb: Blackboard) -> void:
	_step = Step.ANIM_THROW

func tick(actor: Node, _bb: Blackboard) -> int:
	var boss := actor as BossGhostWitch
	if boss == null:
		return FAILURE
	match _step:
		Step.ANIM_THROW:
			boss.anim_play(&"phase1/throw", false)
			_step = Step.WAIT_THROW
		Step.WAIT_THROW:
			if boss.baby_state == BossGhostWitch.BabyState.THROWN:
				_step = Step.WAIT_DONE
		Step.WAIT_DONE:
			if boss.baby_state != BossGhostWitch.BabyState.THROWN:
				return SUCCESS
	return RUNNING

func interrupt(actor: Node, blackboard: Blackboard) -> void:
	_step = Step.ANIM_THROW
	super(actor, blackboard)
