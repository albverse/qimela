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
	mollusc.velocity = Vector2.ZERO
	if player != null and is_instance_valid(player):
		mollusc.escape_dir_x = 1 if player.global_position.x >= mollusc.global_position.x else -1
	_phase = Phase.ATTACK_STONE
	mollusc.anim_play(&"attack_stone", false, false)
	return RUNNING


func _tick_attack_stone(mollusc: Mollusc, player: Node2D) -> int:
	if mollusc.anim_is_finished(&"attack_stone"):
		if mollusc.is_player_in_attack_range() and player != null and is_instance_valid(player):
			if player.has_method("apply_stone_stun"):
				player.call("apply_stone_stun", mollusc.player_stone_stun)
		if mollusc.is_player_in_attack_range():
			_phase = Phase.ATTACK_LICK
			mollusc.anim_play(&"attack_lick", false, false)
		else:
			_phase = Phase.DONE
	return RUNNING


func _tick_attack_lick(mollusc: Mollusc, player: Node2D) -> int:
	if mollusc.anim_is_finished(&"attack_lick"):
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
	_phase = Phase.STOP
	super(actor, blackboard)
