extends ActionLeaf
class_name ActStartBattle

## 首次检测到玩家 → start_attack → start_attack_loop(4s) → start_attack_exter → 战斗开始

enum Step { PLAY_START, WAIT_START, PLAY_LOOP, WAIT_LOOP, PLAY_EXTER, WAIT_EXTER }
var _step: int = Step.PLAY_START
var _loop_end_time: float = 0.0

func before_run(actor: Node, _bb: Blackboard) -> void:
	_step = Step.PLAY_START

func tick(actor: Node, _blackboard: Blackboard) -> int:
	var boss: BossGhostWitch = actor as BossGhostWitch
	if boss == null:
		return FAILURE

	match _step:
		Step.PLAY_START:
			boss.anim_play(&"phase1/start_attack", false)
			_step = Step.WAIT_START
			return RUNNING
		Step.WAIT_START:
			if boss.anim_is_finished(&"phase1/start_attack"):
				_step = Step.PLAY_LOOP
			return RUNNING
		Step.PLAY_LOOP:
			boss.anim_play(&"phase1/start_attack_loop", true)
			_loop_end_time = Time.get_ticks_msec() + boss.start_attack_loop_duration * 1000.0
			_step = Step.WAIT_LOOP
			return RUNNING
		Step.WAIT_LOOP:
			if Time.get_ticks_msec() >= _loop_end_time:
				_step = Step.PLAY_EXTER
			return RUNNING
		Step.PLAY_EXTER:
			boss.anim_play(&"phase1/start_attack_exter", false)
			_step = Step.WAIT_EXTER
			return RUNNING
		Step.WAIT_EXTER:
			if boss.anim_is_finished(&"phase1/start_attack_exter"):
				boss._battle_started = true
				return SUCCESS
			return RUNNING
	return FAILURE

func interrupt(actor: Node, blackboard: Blackboard) -> void:
	_step = Step.PLAY_START
	super(actor, blackboard)
