extends ActionLeaf
class_name ActSoulDevourerKnifeAttackSequence

## =============================================================================
## act_knife_attack_sequence — has_knife 持刀跑位/攻击（P7）
## =============================================================================
## 持刀后先用 has_knife/run 跑位到玩家后方安全距离；
## 通过专用 KnifeAttackTriggerArea 实时检测玩家是否进入起手范围；
## 每次攻击后都先继续向前直线跑出 200px，再做后续衔接；
## 前两次攻击跑出后播 has_knife/attack_over，再折回下一轮跑位；
## 第三次攻击跑出后播 has_knife/change_to_normal 并进入 10s 冷却。
## =============================================================================

const PICKUP_CD_KEY: StringName = &"sd_cleaver_pickup_cd_end"
const REPOSITION_OFFSET_X: float = 120.0
const REPOSITION_EPSILON: float = 12.0
const ATTACK_SPEED_MULTIPLIER: float = 4.0
const RUN_SPEED_MULTIPLIER: float = 4.0
const FACE_LOOKAHEAD: float = 100.0
const BLOCKED_PROGRESS_EPSILON: float = 1.0
const BLOCKED_TIME_THRESHOLD: float = 0.2
const POST_ATTACK_RUNOUT_DIST: float = 200.0
const KNIFE_COMBO_LIMIT: int = 3
const KNIFE_COMBO_COOLDOWN: float = 10.0

enum Phase {
	REPOSITION,
	ATTACK,
	ATTACK_OVER,
	EXIT_RUNOUT,
	EXIT_TO_NORMAL,
}

var _phase: int = Phase.REPOSITION
var _run_target_x: float = 0.0
var _run_dir: float = 1.0
var _run_target_locked: bool = false
var _last_reposition_x: float = 0.0
var _blocked_time: float = 0.0
var _post_attack_finish_combo: bool = false
## 攻击方向锁定：攻击开始时锁定，直到 EXIT_RUNOUT 结束不变
var _attack_locked_dir: float = 1.0
## EXIT_TO_NORMAL 阶段是否已提前设置了拾刀 CD（防止 throw_cleaver 事件导致 P6 抢占）
var _exit_cd_applied: bool = false


func before_run(actor: Node, _blackboard: Blackboard) -> void:
	var sd: SoulDevourer = actor as SoulDevourer
	if sd == null:
		return
	sd._knife_attack_count = clampi(sd._knife_attack_count, 0, KNIFE_COMBO_LIMIT)
	_run_target_locked = false
	_last_reposition_x = sd.global_position.x
	_blocked_time = 0.0
	_post_attack_finish_combo = false
	_attack_locked_dir = 1.0
	_exit_cd_applied = false

	# 安全检查：若 combo 已满（不应发生，但防止卡死），直接进入 EXIT_TO_NORMAL
	if sd._knife_attack_count >= KNIFE_COMBO_LIMIT:
		_enter_exit_to_normal(sd, _blackboard)
		print("[SD:P7] before_run: combo=%d >= limit, skip to EXIT_TO_NORMAL" % sd._knife_attack_count)
		return

	_phase = Phase.REPOSITION
	_enter_reposition(sd)


func tick(actor: Node, blackboard: Blackboard) -> int:
	var sd: SoulDevourer = actor as SoulDevourer
	if sd == null:
		return FAILURE

	match _phase:
		Phase.REPOSITION:
			return _tick_reposition(sd, blackboard)
		Phase.ATTACK:
			return _tick_attack(sd, blackboard)
		Phase.ATTACK_OVER:
			return _tick_attack_over(sd)
		Phase.EXIT_RUNOUT:
			return _tick_exit_runout(sd, blackboard)
		Phase.EXIT_TO_NORMAL:
			return _tick_exit_to_normal(sd, blackboard)

	return RUNNING


func _tick_reposition(sd: SoulDevourer, blackboard: Blackboard) -> int:
	var player: Node2D = sd.get_priority_attack_target()
	if player == null:
		sd.velocity.x = 0.0
		sd.anim_play(&"has_knife/idle", true)
		if Engine.get_physics_frames() % 60 == 0:
			print("[SD:P7] HOLD: no player target, staying has_knife/idle")
		return RUNNING

	# 安全检查：combo 已满时直接进入退出流程
	if sd._knife_attack_count >= KNIFE_COMBO_LIMIT:
		_enter_exit_to_normal(sd, blackboard)
		print("[SD:P7] REPOSITION→EXIT_TO_NORMAL: combo=%d >= limit" % sd._knife_attack_count)
		return RUNNING

	var dx_to_player: float = player.global_position.x - sd.global_position.x
	var dt: float = get_physics_process_delta_time()
	if not _run_target_locked:
		_lock_run_target(sd, player)
	var target_x: float = _run_target_x
	var dx_to_target: float = target_x - sd.global_position.x

	# 实时检测：玩家进入 KnifeAttackTriggerArea 即可触发攻击
	if _can_start_attack(sd, player, dx_to_player):
		_start_attack(sd, player)
		return RUNNING

	if absf(dx_to_target) <= REPOSITION_EPSILON:
		_lock_run_target(sd, player)
		target_x = _run_target_x
		dx_to_target = target_x - sd.global_position.x

	_run_dir = sign(dx_to_target) if not is_zero_approx(dx_to_target) else _run_dir
	sd.velocity.x = _run_dir * sd.ground_run_speed * RUN_SPEED_MULTIPLIER
	sd.face_toward_position(sd.global_position.x + _run_dir * FACE_LOOKAHEAD)
	sd.anim_play(&"has_knife/run", true)
	if absf(sd.global_position.x - _last_reposition_x) <= BLOCKED_PROGRESS_EPSILON:
		_blocked_time += dt
	else:
		_blocked_time = 0.0
	_last_reposition_x = sd.global_position.x
	if _blocked_time >= BLOCKED_TIME_THRESHOLD:
		if _can_attack_while_blocked(sd, player, dx_to_player):
			print("[SD:P7] BLOCKED→ATTACK: player_x=%.1f sd_x=%.1f dx_player=%.1f blocked_t=%.2f" % [
				player.global_position.x, sd.global_position.x, dx_to_player, _blocked_time])
			_start_attack(sd, player)
			return RUNNING
		_flip_reposition_target(sd, player)
		if Engine.get_physics_frames() % 30 == 0:
			print("[SD:P7] BLOCKED FLIP: new_target_x=%.1f player_x=%.1f sd_x=%.1f blocked_t=%.2f" % [
				_run_target_x, player.global_position.x, sd.global_position.x, _blocked_time])
		return RUNNING

	if Engine.get_physics_frames() % 30 == 0:
		print("[SD:P7] REPOSITION: target_x=%.1f player_x=%.1f sd_x=%.1f dx_player=%.1f vel=%.1f combo=%d in_trigger=%s" % [
			target_x, player.global_position.x, sd.global_position.x, dx_to_player, sd.velocity.x,
			sd._knife_attack_count, sd.is_player_in_knife_attack_trigger(player)])
	return RUNNING


func _start_attack(sd: SoulDevourer, player: Node2D) -> void:
	_phase = Phase.ATTACK
	# 锁定攻击方向：从 SD 朝向玩家的方向，攻击期间不再改变
	var dx: float = player.global_position.x - sd.global_position.x
	_attack_locked_dir = sign(dx) if not is_zero_approx(dx) else _run_dir
	sd.velocity.x = 0.0
	sd.face_toward_position(player.global_position.x)
	sd.anim_play(&"has_knife/knife_attack_run", false)
	print("[SD:P7] ATTACK START: player_x=%.1f sd_x=%.1f dir=%.1f" % [
		player.global_position.x, sd.global_position.x, _attack_locked_dir])


func _tick_attack(sd: SoulDevourer, _blackboard: Blackboard) -> int:
	# 攻击期间使用锁定方向，不重新面向玩家（防止折返）
	sd.velocity.x = _attack_locked_dir * sd.ground_run_speed * ATTACK_SPEED_MULTIPLIER

	if sd.anim_is_finished(&"has_knife/knife_attack_run"):
		sd._knife_attack_count += 1
		print("[SD:P7] ATTACK DONE: combo=%d/%d" % [sd._knife_attack_count, KNIFE_COMBO_LIMIT])
		_start_post_attack_runout(sd, sd._knife_attack_count >= KNIFE_COMBO_LIMIT)
	return RUNNING


func _enter_reposition(sd: SoulDevourer) -> void:
	_phase = Phase.REPOSITION
	_last_reposition_x = sd.global_position.x
	_blocked_time = 0.0
	_run_target_locked = false
	sd.velocity.x = 0.0
	sd.anim_play(&"has_knife/run", true)


func _start_post_attack_runout(sd: SoulDevourer, finish_combo: bool) -> void:
	_phase = Phase.EXIT_RUNOUT
	_post_attack_finish_combo = finish_combo
	_run_target_locked = true
	# 攻击后继续沿攻击方向直线跑出 200px（不折返）
	_run_dir = _attack_locked_dir
	_run_target_x = sd.global_position.x + _run_dir * POST_ATTACK_RUNOUT_DIST
	_last_reposition_x = sd.global_position.x
	_blocked_time = 0.0
	sd.velocity.x = _run_dir * sd.ground_run_speed * RUN_SPEED_MULTIPLIER
	sd.face_toward_position(sd.global_position.x + _run_dir * FACE_LOOKAHEAD)
	sd.anim_play(&"has_knife/run", true)


func _tick_attack_over(sd: SoulDevourer) -> int:
	sd.velocity.x = 0.0
	if not sd.anim_is_playing(&"has_knife/attack_over") and not sd.anim_is_finished(&"has_knife/attack_over"):
		sd.anim_play(&"has_knife/attack_over", false)
	if sd.anim_is_finished(&"has_knife/attack_over"):
		_post_attack_finish_combo = false
		_enter_reposition(sd)
	return RUNNING


func _tick_exit_runout(sd: SoulDevourer, blackboard: Blackboard) -> int:
	var dx_to_target: float = _run_target_x - sd.global_position.x
	var dt: float = get_physics_process_delta_time()

	if absf(dx_to_target) <= REPOSITION_EPSILON:
		sd.velocity.x = 0.0
		if _post_attack_finish_combo:
			_enter_exit_to_normal(sd, blackboard)
		else:
			_phase = Phase.ATTACK_OVER
			sd.anim_play(&"has_knife/attack_over", false)
		return RUNNING

	# 检测是否被墙阻挡
	if absf(sd.global_position.x - _last_reposition_x) <= BLOCKED_PROGRESS_EPSILON:
		_blocked_time += dt
	else:
		_blocked_time = 0.0
	_last_reposition_x = sd.global_position.x

	# 被阻挡超过阈值时提前结束 runout
	if _blocked_time >= BLOCKED_TIME_THRESHOLD:
		sd.velocity.x = 0.0
		if _post_attack_finish_combo:
			_enter_exit_to_normal(sd, blackboard)
		else:
			_phase = Phase.ATTACK_OVER
			sd.anim_play(&"has_knife/attack_over", false)
		print("[SD:P7] EXIT_RUNOUT blocked, transitioning early")
		return RUNNING

	# 保持攻击方向直线运动（不折返）
	sd.velocity.x = _run_dir * sd.ground_run_speed * RUN_SPEED_MULTIPLIER
	sd.face_toward_position(sd.global_position.x + _run_dir * FACE_LOOKAHEAD)
	sd.anim_play(&"has_knife/run", true)
	return RUNNING


## 进入 EXIT_TO_NORMAL 阶段：立即设置拾刀 CD + 重置 combo
## 必须在 change_to_normal 动画播放前调用，防止 throw_cleaver 事件期间 P6 抢占
func _enter_exit_to_normal(sd: SoulDevourer, blackboard: Blackboard) -> void:
	_phase = Phase.EXIT_TO_NORMAL
	sd.velocity.x = 0.0
	# 立即设置拾刀冷却（关键：必须在 throw_cleaver 事件触发前锁定 CD）
	if not _exit_cd_applied:
		_exit_cd_applied = true
		sd._knife_attack_count = 0
		var actor_id: String = str(sd.get_instance_id())
		blackboard.set_value(PICKUP_CD_KEY, SoulDevourer.now_sec() + KNIFE_COMBO_COOLDOWN, actor_id)
		print("[SD:P7] EXIT_TO_NORMAL: CD set EARLY (%.1fs), combo reset" % KNIFE_COMBO_COOLDOWN)
	sd.anim_play(&"has_knife/change_to_normal", false)


func _tick_exit_to_normal(sd: SoulDevourer, blackboard: Blackboard) -> int:
	sd.velocity.x = 0.0
	# 每帧补充 CD（防止 interrupt 后重入时未设置的情况）
	if not _exit_cd_applied:
		_exit_cd_applied = true
		sd._knife_attack_count = 0
		var actor_id: String = str(sd.get_instance_id())
		blackboard.set_value(PICKUP_CD_KEY, SoulDevourer.now_sec() + KNIFE_COMBO_COOLDOWN, actor_id)
		print("[SD:P7] EXIT_TO_NORMAL tick: CD set (%.1fs), combo reset" % KNIFE_COMBO_COOLDOWN)
	if not sd.anim_is_playing(&"has_knife/change_to_normal") and not sd.anim_is_finished(&"has_knife/change_to_normal"):
		sd.anim_play(&"has_knife/change_to_normal", false)
	if sd.anim_is_finished(&"has_knife/change_to_normal"):
		sd._has_knife = false
		_post_attack_finish_combo = false
		print("[SD:P7] EXIT_TO_NORMAL done: has_knife=false")
		return SUCCESS
	return RUNNING


func _get_reposition_target_x(player: Node2D) -> float:
	var player_facing: float = _get_player_facing(player)
	return player.global_position.x - player_facing * REPOSITION_OFFSET_X


func _is_player_in_attack_window(sd: SoulDevourer, player: Node2D, _dx_to_player: float) -> bool:
	# 简化判定：只要玩家在 KnifeAttackTriggerArea 内即可触发攻击
	# 不再限制必须在玩家后方，允许任何方向的攻击触发
	return sd.is_player_in_knife_attack_trigger(player)


func _lock_run_target(sd: SoulDevourer, player: Node2D) -> void:
	_run_target_x = _get_reposition_target_x(player)
	var dx_to_target: float = _run_target_x - sd.global_position.x
	if not is_zero_approx(dx_to_target):
		_run_dir = sign(dx_to_target)
	_run_target_locked = true
	_last_reposition_x = sd.global_position.x
	_blocked_time = 0.0


func _flip_reposition_target(sd: SoulDevourer, player: Node2D) -> void:
	_run_dir = -_run_dir if not is_zero_approx(_run_dir) else 1.0
	_run_target_x = player.global_position.x + _run_dir * REPOSITION_OFFSET_X
	_run_target_locked = true
	_last_reposition_x = sd.global_position.x
	_blocked_time = 0.0
	sd.velocity.x = _run_dir * sd.ground_run_speed * RUN_SPEED_MULTIPLIER
	sd.face_toward_position(sd.global_position.x + _run_dir * FACE_LOOKAHEAD)
	sd.anim_play(&"has_knife/run", true)


func _can_attack_while_blocked(sd: SoulDevourer, player: Node2D, dx_to_player: float) -> bool:
	if sd._knife_attack_count >= KNIFE_COMBO_LIMIT:
		return false
	if not sd.is_player_in_knife_attack_trigger(player):
		return false
	var blocked_attack_dist: float = REPOSITION_OFFSET_X + 60.0
	return absf(dx_to_player) <= blocked_attack_dist


func _can_start_attack(sd: SoulDevourer, player: Node2D, dx_to_player: float) -> bool:
	if sd._knife_attack_count >= KNIFE_COMBO_LIMIT:
		return false
	return _is_player_in_attack_window(sd, player, dx_to_player)


func _get_player_facing(player: Node2D) -> float:
	var player_facing: float = 1.0
	if player != null:
		var facing_value = player.get("facing")
		if facing_value != null:
			player_facing = float(facing_value)
	if is_zero_approx(player_facing):
		player_facing = 1.0
	return player_facing


func _cleanup(sd: SoulDevourer) -> void:
	sd.velocity.x = 0.0
	_run_target_locked = false
	_blocked_time = 0.0
	_post_attack_finish_combo = false
	if sd._has_knife:
		sd.anim_play(&"has_knife/idle", true)
	else:
		sd.anim_play(&"normal/idle", true)


func interrupt(actor: Node, blackboard: Blackboard) -> void:
	var sd: SoulDevourer = actor as SoulDevourer
	if sd != null:
		# 若在 EXIT_TO_NORMAL 阶段被中断，确保 CD 已设置（防止 P6 立即抢占拾刀）
		if _phase == Phase.EXIT_TO_NORMAL and not _exit_cd_applied:
			_exit_cd_applied = true
			sd._knife_attack_count = 0
			var actor_id: String = str(sd.get_instance_id())
			blackboard.set_value(PICKUP_CD_KEY, SoulDevourer.now_sec() + KNIFE_COMBO_COOLDOWN, actor_id)
			print("[SD:P7] INTERRUPTED in EXIT_TO_NORMAL: CD set (%.1fs)" % KNIFE_COMBO_COOLDOWN)
		_cleanup(sd)
	super(actor, blackboard)
