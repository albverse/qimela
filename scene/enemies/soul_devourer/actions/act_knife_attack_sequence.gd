extends ActionLeaf
class_name ActSoulDevourerKnifeAttackSequence

## =============================================================================
## act_knife_attack_sequence — has_knife 持刀跑位/攻击（P7）
## =============================================================================
## 持刀后先用 has_knife/run 跑位到玩家后方安全距离；
## 只有玩家进入攻击范围时才切换到 has_knife/knife_attack_run；
## 攻击动画结束后立即回到 has_knife/run，并沿当前直线方向继续前冲，不立刻折返。
## =============================================================================

const ATK_CD_KEY: StringName = &"sd_knife_atk_cd_end"
const REPOSITION_OFFSET_X: float = 120.0
const REPOSITION_EPSILON: float = 12.0
const ATTACK_SPEED_MULTIPLIER: float = 2.5
const RUN_SPEED_MULTIPLIER: float = 2.0
const FACE_LOOKAHEAD: float = 100.0
const BLOCKED_PROGRESS_EPSILON: float = 1.0
const BLOCKED_TIME_THRESHOLD: float = 0.2
const POST_ATTACK_RUNOUT_MULTIPLIER: float = 2.0

enum Phase {
	REPOSITION,
	ATTACK,
}

var _phase: int = Phase.REPOSITION
var _run_target_x: float = 0.0
var _run_dir: float = 1.0
var _run_target_locked: bool = false
var _last_reposition_x: float = 0.0
var _blocked_time: float = 0.0


func before_run(actor: Node, _blackboard: Blackboard) -> void:
	var sd: SoulDevourer = actor as SoulDevourer
	if sd == null:
		return
	_phase = Phase.REPOSITION
	_run_target_locked = false
	_last_reposition_x = sd.global_position.x
	_blocked_time = 0.0
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

	return RUNNING


func _tick_reposition(sd: SoulDevourer, blackboard: Blackboard) -> int:
	var player: Node2D = sd.get_priority_attack_target()
	if player == null:
		sd.velocity.x = 0.0
		sd.anim_play(&"has_knife/idle", true)
		if Engine.get_physics_frames() % 60 == 0:
			print("[SD:P7] HOLD: no player target, staying has_knife/idle")
		return RUNNING

	var dx_to_player: float = player.global_position.x - sd.global_position.x
	var dt: float = get_physics_process_delta_time()
	if not _run_target_locked:
		_lock_run_target(sd, player)
	var target_x: float = _run_target_x
	var dx_to_target: float = target_x - sd.global_position.x
	var attack_ready: bool = _is_attack_ready(sd, blackboard)
	if attack_ready and _is_player_in_attack_window(sd, player, dx_to_player):
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
		if attack_ready and _can_attack_while_blocked(dx_to_player):
			print("[SD:P7] BLOCKED→ATTACK: player_x=%.1f sd_x=%.1f dx_player=%.1f blocked_t=%.2f" % [
				player.global_position.x, sd.global_position.x, dx_to_player, _blocked_time])
			_start_attack(sd, player)
			return RUNNING
		sd.velocity.x = 0.0
		sd.face_toward_position(player.global_position.x)
		sd.anim_play(&"has_knife/idle", true)
		if Engine.get_physics_frames() % 30 == 0:
			print("[SD:P7] BLOCKED HOLD: target_x=%.1f player_x=%.1f sd_x=%.1f dx_player=%.1f blocked_t=%.2f" % [
				target_x, player.global_position.x, sd.global_position.x, dx_to_player, _blocked_time])
		return RUNNING

	if Engine.get_physics_frames() % 30 == 0:
		print("[SD:P7] REPOSITION: target_x=%.1f player_x=%.1f sd_x=%.1f dx_player=%.1f vel=%.1f atk_ready=%s" % [
			target_x, player.global_position.x, sd.global_position.x, dx_to_player, sd.velocity.x, attack_ready])
	return RUNNING


func _start_attack(sd: SoulDevourer, player: Node2D) -> void:
	_phase = Phase.ATTACK
	sd.velocity.x = 0.0
	sd.face_toward_position(player.global_position.x)
	sd.anim_play(&"has_knife/knife_attack_run", false)
	print("[SD:P7] ATTACK START: player_x=%.1f sd_x=%.1f" % [player.global_position.x, sd.global_position.x])


func _tick_attack(sd: SoulDevourer, blackboard: Blackboard) -> int:
	var player: Node2D = sd.get_priority_attack_target()
	if player != null:
		sd.face_toward_position(player.global_position.x)

	var dir: float = 1.0
	if sd._spine_sprite != null and sd._spine_sprite.scale.x != 0.0:
		dir = sign(sd._spine_sprite.scale.x)
	sd.velocity.x = dir * sd.ground_run_speed * ATTACK_SPEED_MULTIPLIER

	if sd.anim_is_finished(&"has_knife/knife_attack_run"):
		var actor_id: String = str(sd.get_instance_id())
		blackboard.set_value(ATK_CD_KEY, SoulDevourer.now_sec() + sd.attack_cooldown_has_knife, actor_id)
		print("[SD:P7] ATTACK DONE → back to run")
		_continue_straight_run(sd)
	return RUNNING


func _enter_reposition(sd: SoulDevourer) -> void:
	_phase = Phase.REPOSITION
	_last_reposition_x = sd.global_position.x
	_blocked_time = 0.0
	sd.velocity.x = 0.0
	sd.anim_play(&"has_knife/run", true)


func _is_attack_ready(sd: SoulDevourer, blackboard: Blackboard) -> bool:
	var actor_id: String = str(sd.get_instance_id())
	var cd_end: float = blackboard.get_value(ATK_CD_KEY, 0.0, actor_id)
	return SoulDevourer.now_sec() >= cd_end


func _continue_straight_run(sd: SoulDevourer) -> void:
	_phase = Phase.REPOSITION
	_run_target_locked = true
	_run_target_x = sd.global_position.x + _run_dir * REPOSITION_OFFSET_X * POST_ATTACK_RUNOUT_MULTIPLIER
	_last_reposition_x = sd.global_position.x
	_blocked_time = 0.0
	sd.velocity.x = _run_dir * sd.ground_run_speed * RUN_SPEED_MULTIPLIER
	sd.face_toward_position(sd.global_position.x + _run_dir * FACE_LOOKAHEAD)
	sd.anim_play(&"has_knife/run", true)


func _get_reposition_target_x(player: Node2D) -> float:
	var player_facing: float = _get_player_facing(player)
	return player.global_position.x - player_facing * REPOSITION_OFFSET_X


func _is_player_in_attack_window(sd: SoulDevourer, player: Node2D, dx_to_player: float) -> bool:
	var player_facing: float = _get_player_facing(player)
	var desired_rear_side: float = -player_facing
	var current_side: float = sign(sd.global_position.x - player.global_position.x)
	if is_zero_approx(current_side):
		current_side = desired_rear_side
	if current_side != desired_rear_side:
		return false
	var attack_window_dist: float = REPOSITION_OFFSET_X + sd.knife_attack_trigger_dist
	if absf(dx_to_player) > attack_window_dist:
		return false
	return sign(dx_to_player) == _run_dir or is_zero_approx(dx_to_player)


func _lock_run_target(sd: SoulDevourer, player: Node2D) -> void:
	_run_target_x = _get_reposition_target_x(player)
	var dx_to_target: float = _run_target_x - sd.global_position.x
	if not is_zero_approx(dx_to_target):
		_run_dir = sign(dx_to_target)
	_run_target_locked = true
	_last_reposition_x = sd.global_position.x
	_blocked_time = 0.0


func _can_attack_while_blocked(dx_to_player: float) -> bool:
	var blocked_attack_dist: float = REPOSITION_OFFSET_X + 60.0
	return absf(dx_to_player) <= blocked_attack_dist


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
	if sd._has_knife:
		sd.anim_play(&"has_knife/idle", true)
	else:
		sd.anim_play(&"normal/idle", true)


func interrupt(actor: Node, blackboard: Blackboard) -> void:
	var sd: SoulDevourer = actor as SoulDevourer
	if sd != null:
		_cleanup(sd)
	super(actor, blackboard)
