extends ActionLeaf
class_name ActMolluscAttack

## 软体虫攻击序列：停步 → attack_stone（石化）→ 若玩家仍在范围 → attack_lick（击退）。
## 每次攻击结束后进入 attack_cd 冷却窗口；冷却中由 BT 走逃跑分支。
##
## 命中时机依赖 Spine 事件：atk1_hit_on / atk1_hit_off / atk2_hit_on / atk2_hit_off。
## Mock 兜底：动画结束点作为命中时机。

enum Phase { STOP, ATTACK_STONE, ATTACK_LICK, DONE }

var _phase: int = Phase.STOP
var _atk1_hit_applied: bool = false
var _atk2_hit_applied: bool = false


func before_run(actor: Node, _blackboard: Blackboard) -> void:
	var mollusc := actor as Mollusc
	if mollusc == null:
		return
	_phase = Phase.STOP
	mollusc.velocity = Vector2.ZERO
	mollusc.is_attacking = true


func tick(actor: Node, blackboard: Blackboard) -> int:
	var mollusc := actor as Mollusc
	if mollusc == null:
		return FAILURE

	var player: Node2D = mollusc.get_player()

	match _phase:
		Phase.STOP:
			return _tick_stop(mollusc, player)
		Phase.ATTACK_STONE:
			return _tick_attack_stone(mollusc, player)
		Phase.ATTACK_LICK:
			return _tick_attack_lick(mollusc, player)
		Phase.DONE:
			mollusc.next_attack_end_ms = Mollusc.now_ms() + int(mollusc.attack_cd * 1000.0)
			mollusc.is_attacking = false
			return SUCCESS
	return RUNNING


func _tick_stop(mollusc: Mollusc, player: Node2D) -> int:
	if mollusc.is_hurt:
		mollusc.is_attacking = false
		return FAILURE
	mollusc.velocity = Vector2.ZERO
	if player != null and is_instance_valid(player):
		mollusc.escape_dir_x = 1 if player.global_position.x >= mollusc.global_position.x else -1
	_phase = Phase.ATTACK_STONE
	_atk1_hit_applied = false
	mollusc.ev_atk1_hit_on = false
	mollusc.ev_atk1_hit_off = false
	mollusc.anim_play(&"attack_stone", false, false)
	return RUNNING


func _tick_attack_stone(mollusc: Mollusc, player: Node2D) -> int:
	if mollusc.is_hurt:
		mollusc.force_close_hit_windows()
		mollusc.is_attacking = false
		return FAILURE
	# Spine atk1_hit_on：立即施加石化
	if not _atk1_hit_applied and mollusc.ev_atk1_hit_on:
		mollusc.ev_atk1_hit_on = false
		_atk1_hit_applied = true
		if mollusc.is_player_in_attack_range() and player != null and is_instance_valid(player):
			if player.has_method("apply_stone_stun"):
				player.call("apply_stone_stun", mollusc.player_stone_stun)
	# Spine atk1_hit_off 或 Mock anim_finished：推进阶段
	if mollusc.ev_atk1_hit_off or mollusc.anim_is_finished(&"attack_stone"):
		mollusc.ev_atk1_hit_off = false
		if not _atk1_hit_applied:
			if mollusc.is_player_in_attack_range() and player != null and is_instance_valid(player):
				if player.has_method("apply_stone_stun"):
					player.call("apply_stone_stun", mollusc.player_stone_stun)
		if mollusc.is_player_in_attack_range():
			_phase = Phase.ATTACK_LICK
			_atk2_hit_applied = false
			mollusc.ev_atk2_hit_on = false
			mollusc.ev_atk2_hit_off = false
			mollusc.anim_play(&"attack_lick", false, false)
		else:
			_phase = Phase.DONE
	return RUNNING


func _tick_attack_lick(mollusc: Mollusc, player: Node2D) -> int:
	if mollusc.is_hurt:
		mollusc.force_close_hit_windows()
		mollusc.is_attacking = false
		return FAILURE
	# Spine atk2_hit_on：立即施加击退
	if not _atk2_hit_applied and mollusc.ev_atk2_hit_on:
		mollusc.ev_atk2_hit_on = false
		_atk2_hit_applied = true
		if mollusc.is_player_in_attack_range() and player != null and is_instance_valid(player):
			_apply_lick_knockback(mollusc, player)
	# Spine atk2_hit_off 或 Mock anim_finished：结束攻击
	if mollusc.ev_atk2_hit_off or mollusc.anim_is_finished(&"attack_lick"):
		mollusc.ev_atk2_hit_off = false
		if not _atk2_hit_applied:
			if mollusc.is_player_in_attack_range() and player != null and is_instance_valid(player):
				_apply_lick_knockback(mollusc, player)
		_phase = Phase.DONE
	return RUNNING


func _apply_lick_knockback(mollusc: Mollusc, player: Node2D) -> void:
	if "velocity" not in player:
		return
	var dir_x := signf(player.global_position.x - mollusc.global_position.x)
	if dir_x == 0.0:
		dir_x = 1.0
	player.set("velocity", Vector2(dir_x * mollusc.knockback_strength, player.get("velocity").y))


func interrupt(actor: Node, blackboard: Blackboard) -> void:
	var mollusc := actor as Mollusc
	if mollusc != null:
		mollusc.velocity = Vector2.ZERO
		mollusc.is_attacking = false
		mollusc.force_close_hit_windows()
	_phase = Phase.STOP
	super(actor, blackboard)
