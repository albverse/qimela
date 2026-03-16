## 婴儿石像的完整攻击循环（多帧状态机）
extends ActionLeaf
class_name ActBabyAttackFlow

enum Step {
	EXPLODE,           # 爆炸动画 + 开启 realhurtbox
	REPAIR,            # 修复动画（期间核心可被 ghostfist 攻击）
	CHECK_PLAYER,      # 修复完毕 → 检测玩家是否在范围内
	DASH_TO_PLAYER,    # 向玩家方向冲刺（蓄力→dash_go→dash_loop移动）
	POST_DASH_WAIT,    # 冲刺到达后等待 0.7s
	DASH_BACK,         # 向冲刺前位置冲回（直接 dash_loop，跳过蓄力）
	WIND_UP,           # 收招动画
	RETURN_HOME,       # 飞回母体
	DONE
}

var _step: int = Step.EXPLODE
var _dash_origin: Vector2 = Vector2.ZERO
var _dash_target: Vector2 = Vector2.ZERO
var _wait_end: float = 0.0

func before_run(actor: Node, _bb: Blackboard) -> void:
	_step = Step.EXPLODE
	var boss := actor as BossGhostWitch
	if boss:
		boss._baby_dash_go_triggered = false

func tick(actor: Node, _blackboard: Blackboard) -> int:
	var boss := actor as BossGhostWitch
	if boss == null:
		return FAILURE
	# 婴儿攻击流期间 Boss 本体不移动
	actor.velocity.x = 0.0

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
	boss.baby_anim_play(&"baby/explode", false)
	# Spine 事件 "explode_hitbox_on" → 开启 BabyExplosionArea 范围伤害
	# Spine 事件 "realhurtbox_on" → boss._set_baby_realhurtbox(true)
	if boss.baby_anim_is_finished(&"baby/explode"):
		boss.baby_state = BossGhostWitch.BabyState.REPAIRING
		_step = Step.REPAIR
	return RUNNING

func _tick_repair(boss: BossGhostWitch) -> int:
	boss.baby_anim_play(&"baby/repair", false)
	# 修复期间 realhurtbox 保持开启，ghostfist 可以攻击核心
	if boss.baby_anim_is_finished(&"baby/repair"):
		# Spine 事件 "realhurtbox_off" → boss._set_baby_realhurtbox(false)
		_step = Step.CHECK_PLAYER
	return RUNNING

func _tick_check_player(boss: BossGhostWitch) -> int:
	# 检测玩家是否在 BabyDetectArea 范围内
	var player_in_range: bool = false
	if boss._baby_detect_area.monitoring:
		for body in boss._baby_detect_area.get_overlapping_bodies():
			if body.is_in_group("player"):
				player_in_range = true
				break

	if player_in_range:
		_dash_origin = boss._baby_statue.global_position
		var player := boss.get_priority_attack_target()
		_dash_target = player.global_position if player != null else _dash_origin
		boss.baby_state = BossGhostWitch.BabyState.DASHING
		boss._baby_dash_go_triggered = false
		_step = Step.DASH_TO_PLAYER
	else:
		# 玩家不在范围内，跳过冲刺，直接收招返航
		boss.baby_state = BossGhostWitch.BabyState.WINDING_UP
		_step = Step.WIND_UP
	return RUNNING

func _tick_dash(boss: BossGhostWitch, to_player: bool) -> int:
	var target := _dash_target if to_player else _dash_origin
	var baby := boss._baby_statue
	var dt := get_physics_process_delta_time()

	if to_player:
		# 冲刺去：先播蓄力动画，等 dash_go 事件后切到 dash_loop
		if not boss._baby_dash_go_triggered:
			boss.baby_anim_play(&"baby/dash", false)
			return RUNNING
		# dash_go 已触发，切到冲刺循环动画
		boss.baby_anim_play(&"baby/dash_loop", true)
	else:
		# 冲刺回：跳过蓄力，直接播冲刺循环动画
		boss.baby_anim_play(&"baby/dash_loop", true)

	var dir: float = signf(target.x - baby.global_position.x)
	baby.global_position.x += dir * boss.baby_dash_speed * dt

	# 冲刺期间检测碰撞伤害（monitoring 由 Spine 事件 dash_hitbox_on 开启）
	if boss._baby_attack_area.monitoring:
		for body in boss._baby_attack_area.get_overlapping_bodies():
			if body.is_in_group("player") and body.has_method("apply_damage"):
				body.call("apply_damage", 1, baby.global_position)

	if abs(target.x - baby.global_position.x) < 10.0:
		baby.global_position.x = target.x
		boss._baby_dash_go_triggered = false  # 重置
		if to_player:
			_wait_end = Time.get_ticks_msec() + boss.baby_post_dash_wait * 1000.0
			boss.baby_state = BossGhostWitch.BabyState.POST_DASH_WAIT
			_step = Step.POST_DASH_WAIT
		else:
			boss.baby_state = BossGhostWitch.BabyState.WINDING_UP
			_step = Step.WIND_UP
	return RUNNING

func _tick_wait(boss: BossGhostWitch) -> int:
	boss.baby_anim_play(&"baby/idle", true)
	if Time.get_ticks_msec() >= _wait_end:
		boss.baby_state = BossGhostWitch.BabyState.DASHING
		_step = Step.DASH_BACK
	return RUNNING

func _tick_wind_up(boss: BossGhostWitch) -> int:
	boss.baby_anim_play(&"baby/wind_up", false)
	if boss.baby_anim_is_finished(&"baby/wind_up"):
		boss.baby_state = BossGhostWitch.BabyState.RETURNING
		_step = Step.RETURN_HOME
	return RUNNING

func _tick_return(boss: BossGhostWitch) -> int:
	boss.baby_anim_play(&"baby/return", true)
	var target_pos := boss._mark_hug.global_position
	var baby := boss._baby_statue
	var dir := (target_pos - baby.global_position).normalized()
	baby.global_position += dir * boss.baby_return_speed * get_physics_process_delta_time()

	if baby.global_position.distance_to(target_pos) < 10.0:
		baby.global_position = target_pos
		boss.baby_state = BossGhostWitch.BabyState.IN_HUG
		boss.anim_play(&"phase1/catch_baby", false)
		return SUCCESS
	return RUNNING

func interrupt(actor: Node, blackboard: Blackboard) -> void:
	_step = Step.EXPLODE
	var boss := actor as BossGhostWitch
	if boss:
		boss._baby_dash_go_triggered = false
		boss._set_hitbox_enabled(boss._baby_attack_area, false)
		boss._set_hitbox_enabled(boss._baby_explosion_area, false)
		boss._set_baby_realhurtbox(false)
	super(actor, blackboard)
