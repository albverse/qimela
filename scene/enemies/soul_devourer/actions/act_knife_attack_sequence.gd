extends ActionLeaf
class_name ActSoulDevourerKnifeAttackSequence

## =============================================================================
## act_knife_attack_sequence — has_knife 持刀跑位/攻击（P7）
## =============================================================================
## 持刀后先用 has_knife/run 跑位到玩家后方安全距离；
## 只有玩家进入攻击范围时才切换到 has_knife/knife_attack_run；
## 攻击动画结束后立即回到 has_knife/run，继续下一轮跑位。
## =============================================================================

const ATK_CD_KEY: StringName = &"sd_knife_atk_cd_end"
const REPOSITION_OFFSET_X: float = 120.0
const REPOSITION_EPSILON: float = 12.0
const ATTACK_SPEED_MULTIPLIER: float = 2.5

enum Phase {
	REPOSITION,
	ATTACK,
}

var _phase: int = Phase.REPOSITION


func before_run(actor: Node, _blackboard: Blackboard) -> void:
	var sd: SoulDevourer = actor as SoulDevourer
	if sd == null:
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
	var target_x: float = _get_reposition_target_x(player)
	var dx_to_target: float = target_x - sd.global_position.x
	var attack_ready: bool = _is_attack_ready(sd, blackboard)
	if attack_ready and _is_player_in_attack_window(sd, player, dx_to_player, dx_to_target):
		_start_attack(sd, player)
		return RUNNING

	if absf(dx_to_target) <= REPOSITION_EPSILON:
		sd.velocity.x = 0.0
		sd.face_toward_position(player.global_position.x)
		sd.anim_play(&"has_knife/run", true)
		if Engine.get_physics_frames() % 45 == 0:
			print("[SD:P7] HOLD REAR: target_x=%.1f player_x=%.1f sd_x=%.1f dx_player=%.1f atk_ready=%s" % [
				target_x, player.global_position.x, sd.global_position.x, dx_to_player, attack_ready])
		return RUNNING

	var dir: float = sign(dx_to_target)
	sd.velocity.x = dir * sd.ground_run_speed
	sd.face_toward_position(target_x)
	sd.anim_play(&"has_knife/run", true)

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
		_enter_reposition(sd)
	return RUNNING


func _enter_reposition(sd: SoulDevourer) -> void:
	_phase = Phase.REPOSITION
	sd.velocity.x = 0.0
	sd.anim_play(&"has_knife/run", true)


func _is_attack_ready(sd: SoulDevourer, blackboard: Blackboard) -> bool:
	var actor_id: String = str(sd.get_instance_id())
	var cd_end: float = blackboard.get_value(ATK_CD_KEY, 0.0, actor_id)
	return SoulDevourer.now_sec() >= cd_end


func _get_reposition_target_x(player: Node2D) -> float:
	var player_facing: float = _get_player_facing(player)
	return player.global_position.x - player_facing * REPOSITION_OFFSET_X


func _is_player_in_attack_window(sd: SoulDevourer, player: Node2D, dx_to_player: float, dx_to_target: float) -> bool:
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
	if absf(dx_to_target) <= REPOSITION_EPSILON:
		return true
	return absf(dx_to_target) < REPOSITION_OFFSET_X * 0.5


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
	if sd._has_knife:
		sd.anim_play(&"has_knife/idle", true)
	else:
		sd.anim_play(&"normal/idle", true)


func interrupt(actor: Node, blackboard: Blackboard) -> void:
	var sd: SoulDevourer = actor as SoulDevourer
	if sd != null:
		_cleanup(sd)
	super(actor, blackboard)
