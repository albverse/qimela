extends ActionLeaf
class_name ActMolluscAttack

## 软体虫攻击序列：停步 → attack_stone（石化）→ 若玩家仍在范围 → attack_lick（击退）。
## 软体攻击无 2s 冷却（蓝图规格确认）。

enum Phase { STOP, ATTACK_STONE, ATTACK_LICK, DONE }

var _phase: int = Phase.STOP


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

	var player: Node2D = blackboard.get_value("player") as Node2D

	match _phase:
		Phase.STOP:
			return _tick_stop(mollusc, player)
		Phase.ATTACK_STONE:
			return _tick_attack_stone(mollusc, player)
		Phase.ATTACK_LICK:
			return _tick_attack_lick(mollusc, player)
		Phase.DONE:
			mollusc.is_attacking = false
			return SUCCESS
	return RUNNING


func _tick_stop(mollusc: Mollusc, player: Node2D) -> int:
	# 受击/死亡中不允许开始攻击
	if mollusc.is_hurt or mollusc._die_anim_playing:
		mollusc.is_attacking = false
		return FAILURE
	mollusc.velocity = Vector2.ZERO
	if player != null and is_instance_valid(player):
		mollusc.escape_dir_x = 1 if player.global_position.x >= mollusc.global_position.x else -1
	_phase = Phase.ATTACK_STONE
	mollusc.anim_play(&"attack_stone", false, false)
	mollusc.atk1_window_open = true  # 命中窗口开（atk1_hit_on 等效）
	return RUNNING


func _tick_attack_stone(mollusc: Mollusc, player: Node2D) -> int:
	# 受击打断 → 强制关窗 → 进 hurt（已由 apply_hit 触发）
	if mollusc.is_hurt or mollusc._die_anim_playing:
		mollusc.force_close_hit_windows()
		mollusc.is_attacking = false
		return FAILURE
	if mollusc.anim_is_finished(&"attack_stone"):
		mollusc.atk1_window_open = false  # 命中窗口关（atk1_hit_off 等效）
		if mollusc.is_player_in_attack_range() and player != null and is_instance_valid(player):
			if player.has_method("apply_stone_stun"):
				player.call("apply_stone_stun", mollusc.player_stone_stun)
		if mollusc.is_player_in_attack_range():
			_phase = Phase.ATTACK_LICK
			mollusc.anim_play(&"attack_lick", false, false)
			mollusc.atk2_window_open = true  # 命中窗口开（atk2_hit_on 等效）
		else:
			_phase = Phase.DONE
	return RUNNING


func _tick_attack_lick(mollusc: Mollusc, player: Node2D) -> int:
	# 受击打断
	if mollusc.is_hurt or mollusc._die_anim_playing:
		mollusc.force_close_hit_windows()
		mollusc.is_attacking = false
		return FAILURE
	if mollusc.anim_is_finished(&"attack_lick"):
		mollusc.atk2_window_open = false  # 命中窗口关（atk2_hit_off 等效）
		if mollusc.is_player_in_attack_range() and player != null and is_instance_valid(player):
			if "velocity" in player:
				var dir_x := signf(player.global_position.x - mollusc.global_position.x)
				if dir_x == 0.0:
					dir_x = 1.0
				player.set("velocity", Vector2(dir_x * mollusc.knockback_strength, player.get("velocity").y))
		_phase = Phase.DONE
	return RUNNING


func interrupt(actor: Node, blackboard: Blackboard) -> void:
	var mollusc := actor as Mollusc
	if mollusc != null:
		mollusc.velocity = Vector2.ZERO
		mollusc.is_attacking = false
		mollusc.force_close_hit_windows()  # 强制关命中窗口
	_phase = Phase.STOP
	super(actor, blackboard)
