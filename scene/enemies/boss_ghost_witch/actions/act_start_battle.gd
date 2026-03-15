extends ActionLeaf
class_name ActStartBattle

enum Step { PLAY_START, WAIT_START, PLAY_LOOP, WAIT_LOOP, PLAY_EXTER, WAIT_EXTER }
var _step: int = Step.PLAY_START
var _loop_end_ms: float = 0.0

func before_run(_actor: Node, _bb: Blackboard) -> void:
	_step = Step.PLAY_START

func tick(actor: Node, _bb: Blackboard) -> int:
	var boss := actor as BossGhostWitch
	if boss == null:
		return FAILURE
	match _step:
		Step.PLAY_START:
			boss.anim_play(&"phase1/start_attack", false)
			_step = Step.WAIT_START
		Step.WAIT_START:
			if boss.anim_is_finished(&"phase1/start_attack"):
				_step = Step.PLAY_LOOP
		Step.PLAY_LOOP:
			boss.anim_play(&"phase1/start_attack_loop", true)
			_loop_end_ms = Time.get_ticks_msec() + boss.start_attack_loop_duration * 1000.0
			_step = Step.WAIT_LOOP
		Step.WAIT_LOOP:
			if Time.get_ticks_msec() >= _loop_end_ms:
				_step = Step.PLAY_EXTER
		Step.PLAY_EXTER:
			boss.anim_play(&"phase1/start_attack_exter", false)
			_step = Step.WAIT_EXTER
		Step.WAIT_EXTER:
			if boss.anim_is_finished(&"phase1/start_attack_exter"):
				boss._battle_started = true
				return SUCCESS
	return RUNNING

func interrupt(actor: Node, blackboard: Blackboard) -> void:
	_step = Step.PLAY_START
	super(actor, blackboard)
