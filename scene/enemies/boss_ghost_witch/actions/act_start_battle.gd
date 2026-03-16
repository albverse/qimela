## Boss 出场静默等待 → 检测到玩家 → start_attack → start_attack_loop(4s) → start_attack_exter → 战斗开始
## 玩家检测在 Action 内部处理，避免 SequenceReactive 重评估条件导致中断
extends ActionLeaf
class_name ActStartBattle

enum Step { IDLE_WAIT, PLAY_START, WAIT_START, PLAY_LOOP, WAIT_LOOP, PLAY_EXTER, WAIT_EXTER, DONE }
var _step: int = Step.IDLE_WAIT
var _loop_end_time: float = 0.0

func before_run(actor: Node, _bb: Blackboard) -> void:
	_step = Step.IDLE_WAIT

func tick(actor: Node, _blackboard: Blackboard) -> int:
	var boss := actor as BossGhostWitch
	if boss == null:
		return FAILURE

	actor.velocity.x = 0.0

	match _step:
		Step.IDLE_WAIT:
			# Boss 出场后保持静默，播放 idle 动画，等待首次检测到玩家
			boss.anim_play(&"phase1/idle", true)
			var player := boss.get_priority_attack_target()
			if player != null:
				var dist: float = absf(player.global_position.x - actor.global_position.x)
				if dist <= boss.detect_range_px:
					_step = Step.PLAY_START
			return RUNNING
		Step.PLAY_START:
			boss.anim_play(&"phase1/start_attack", false)
			_step = Step.WAIT_START
			return RUNNING
		Step.WAIT_START:
			if boss.anim_is_finished(&"phase1/start_attack"):
				# 检测玩家是否在镰刀检测区
				if _player_in_scythe_area(boss):
					_damage_player(boss, 1)
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

func _player_in_scythe_area(boss: BossGhostWitch) -> bool:
	if not boss._scythe_detect_area.monitoring:
		return false
	for body in boss._scythe_detect_area.get_overlapping_bodies():
		if body.is_in_group("player"):
			return true
	return false

func _damage_player(boss: BossGhostWitch, amount: int) -> void:
	if not boss._scythe_detect_area.monitoring:
		return
	for body in boss._scythe_detect_area.get_overlapping_bodies():
		if body.is_in_group("player") and body.has_method("apply_damage"):
			body.call("apply_damage", amount, boss.global_position)

func interrupt(actor: Node, blackboard: Blackboard) -> void:
	_step = Step.IDLE_WAIT
	super(actor, blackboard)
