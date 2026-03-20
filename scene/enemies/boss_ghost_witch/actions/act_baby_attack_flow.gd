extends ActionLeaf
class_name ActBabyAttackFlow

## 婴儿石像完整攻击循环：爆炸→修复→检测→冲刺→等待→冲回→收招→返航

enum Step {
	EXPLODE, REPAIR, CHECK_PLAYER,
	DASH_TO_PLAYER, POST_DASH_WAIT, DASH_BACK,
	WIND_UP, RETURN_HOME
}

var _step: int = Step.EXPLODE
var _dash_origin: Vector2 = Vector2.ZERO
var _dash_target: Vector2 = Vector2.ZERO
var _wait_end: float = 0.0
var _anim_started: bool = false

func before_run(actor: Node, _bb: Blackboard) -> void:
	_step = Step.EXPLODE
	_anim_started = false
	var boss: BossGhostWitch = actor as BossGhostWitch
	if boss:
		boss._baby_dash_go_triggered = false

func tick(actor: Node, _blackboard: Blackboard) -> int:
	var boss: BossGhostWitch = actor as BossGhostWitch
	if boss == null:
		return FAILURE

	match _step:
		Step.EXPLODE:
			return _tick_explode(boss)
		Step.REPAIR:
			return _tick_repair(boss)
		Step.CHECK_PLAYER:
			return _tick_check_player(boss)
		Step.DASH_TO_PLAYER:
			return _tick_dash(boss, true)
		Step.POST_DASH_WAIT:
			return _tick_wait(boss)
		Step.DASH_BACK:
			return _tick_dash(boss, false)
		Step.WIND_UP:
			return _tick_wind_up(boss)
		Step.RETURN_HOME:
			return _tick_return(boss)
	return FAILURE

func _tick_explode(boss: BossGhostWitch) -> int:
	if boss.baby_state != BossGhostWitch.BabyState.EXPLODED:
		return RUNNING
	if not _anim_started:
		boss.baby_anim_play(&"baby/explode", false)
		_anim_started = true
	if boss.baby_anim_is_finished(&"baby/explode"):
		boss.baby_state = BossGhostWitch.BabyState.REPAIRING
		_step = Step.REPAIR
		_anim_started = false
	return RUNNING

func _tick_repair(boss: BossGhostWitch) -> int:
	if not _anim_started:
		boss.baby_anim_play(&"baby/repair", false)
		_anim_started = true
	if boss.baby_anim_is_finished(&"baby/repair"):
		_step = Step.CHECK_PLAYER
		_anim_started = false
	return RUNNING

func _tick_check_player(boss: BossGhostWitch) -> int:
	var player_in_range: bool = false
	for body: Node2D in boss._baby_detect_area.get_overlapping_bodies():
		if body.is_in_group("player"):
			player_in_range = true
			break
	if player_in_range:
		_dash_origin = boss._baby_statue.global_position
		var player: Node2D = boss.get_priority_attack_target()
		_dash_target = player.global_position if player != null else _dash_origin
		boss.baby_state = BossGhostWitch.BabyState.DASHING
		boss._baby_dash_go_triggered = false
		_step = Step.DASH_TO_PLAYER
		_anim_started = false
	else:
		boss.baby_state = BossGhostWitch.BabyState.WINDING_UP
		_step = Step.WIND_UP
		_anim_started = false
	return RUNNING

func _tick_dash(boss: BossGhostWitch, to_player: bool) -> int:
	var target: Vector2 = _dash_target if to_player else _dash_origin
	var baby: Node2D = boss._baby_statue
	var dt: float = get_physics_process_delta_time()

	if to_player:
		if not boss._baby_dash_go_triggered:
			boss.baby_anim_play(&"baby/dash", false)
			return RUNNING
		boss.baby_anim_play(&"baby/dash_loop", true)
	else:
		boss.baby_anim_play(&"baby/dash_loop", true)

	var dir: float = sign(target.x - baby.global_position.x)
	baby.global_position.x += dir * boss.baby_dash_speed * dt

	if abs(target.x - baby.global_position.x) < 10.0:
		baby.global_position.x = target.x
		boss._baby_dash_go_triggered = false
		boss._set_hitbox_enabled(boss._baby_attack_area, false)
		if to_player:
			_wait_end = Time.get_ticks_msec() + boss.baby_post_dash_wait * 1000.0
			boss.baby_state = BossGhostWitch.BabyState.POST_DASH_WAIT
			_step = Step.POST_DASH_WAIT
		else:
			boss.baby_state = BossGhostWitch.BabyState.WINDING_UP
			_step = Step.WIND_UP
			_anim_started = false
	return RUNNING

func _tick_wait(boss: BossGhostWitch) -> int:
	boss.baby_anim_play(&"baby/idle", true)
	if Time.get_ticks_msec() >= _wait_end:
		boss.baby_state = BossGhostWitch.BabyState.DASHING
		boss._baby_dash_go_triggered = false
		_step = Step.DASH_BACK
	return RUNNING

func _tick_wind_up(boss: BossGhostWitch) -> int:
	if not _anim_started:
		boss.baby_anim_play(&"baby/wind_up", false)
		_anim_started = true
	if boss.baby_anim_is_finished(&"baby/wind_up"):
		boss.baby_state = BossGhostWitch.BabyState.RETURNING
		_step = Step.RETURN_HOME
		_anim_started = false
	return RUNNING

func _tick_return(boss: BossGhostWitch) -> int:
	if not _anim_started:
		boss.baby_anim_play(&"baby/return", true)
		_anim_started = true
	var target_pos: Vector2 = boss._mark_hug.global_position
	var baby: Node2D = boss._baby_statue
	var dir: Vector2 = (target_pos - baby.global_position).normalized()
	baby.global_position += dir * boss.baby_return_speed * get_physics_process_delta_time()
	if baby.global_position.distance_to(target_pos) < 10.0:
		baby.global_position = target_pos
		boss.baby_state = BossGhostWitch.BabyState.IN_HUG
		boss.anim_play(&"phase1/catch_baby", false)
		return SUCCESS
	return RUNNING

func interrupt(actor: Node, blackboard: Blackboard) -> void:
	_step = Step.EXPLODE
	_anim_started = false
	var boss: BossGhostWitch = actor as BossGhostWitch
	if boss:
		boss._baby_dash_go_triggered = false
		boss._set_hitbox_enabled(boss._baby_attack_area, false)
		boss._set_hitbox_enabled(boss._baby_explosion_area, false)
		boss._set_baby_realhurtbox(false)
	super(actor, blackboard)
