extends ActionLeaf
class_name ActSEBAttack

## 石眼虫攻击序列：停步 → 朝向玩家 → attack_stone（石化）→ attack_lick（击退）→ 设冷却。
## 攻击冷却在此 ActionLeaf 内自管理（写入 seb.next_attack_end_ms），
## 不使用 CooldownDecorator（会被 SelectorReactive interrupt 重置）。

enum Phase { STOP, ATTACK_STONE, ATTACK_LICK, DONE }

var _phase: int = Phase.STOP


func before_run(actor: Node, _blackboard: Blackboard) -> void:
	var seb := actor as StoneEyeBug
	if seb == null:
		return
	_phase = Phase.STOP
	seb.velocity = Vector2.ZERO


func tick(actor: Node, blackboard: Blackboard) -> int:
	var seb := actor as StoneEyeBug
	if seb == null:
		return FAILURE

	var player: Node2D = blackboard.get_value("player") as Node2D

	match _phase:
		Phase.STOP:
			return _tick_stop(seb, player)
		Phase.ATTACK_STONE:
			return _tick_attack_stone(seb, player)
		Phase.ATTACK_LICK:
			return _tick_attack_lick(seb, player)
		Phase.DONE:
			return SUCCESS
	return RUNNING


func _tick_stop(seb: StoneEyeBug, player: Node2D) -> int:
	seb.velocity = Vector2.ZERO
	# 朝向玩家
	if player != null and is_instance_valid(player):
		seb.facing = 1 if player.global_position.x >= seb.global_position.x else -1
	_phase = Phase.ATTACK_STONE
	seb.anim_play(&"attack_stone", false, false)
	return RUNNING


func _tick_attack_stone(seb: StoneEyeBug, player: Node2D) -> int:
	if seb.anim_is_finished(&"attack_stone"):
		# 命中判定：玩家是否仍在检测区
		if seb.is_player_in_detect_area() and player != null and is_instance_valid(player):
			_apply_stone_stun(seb, player)
		# 检查玩家是否仍在范围内，若是则接攻击2
		if seb.is_player_in_detect_area():
			_phase = Phase.ATTACK_LICK
			seb.anim_play(&"attack_lick", false, false)
		else:
			_finish_attack(seb)
	return RUNNING


func _apply_stone_stun(seb: StoneEyeBug, player: Node2D) -> void:
	## 对玩家施加石化僵直（通过 EventBus 或玩家接口）
	if player.has_method("apply_stone_stun"):
		player.call("apply_stone_stun", seb.player_stone_stun)


func _tick_attack_lick(seb: StoneEyeBug, player: Node2D) -> int:
	if seb.anim_is_finished(&"attack_lick"):
		# 命中判定：将玩家击退到检测区以外
		if seb.is_player_in_detect_area() and player != null and is_instance_valid(player):
			_apply_lick_knockback(seb, player)
		_finish_attack(seb)
	return RUNNING


func _apply_lick_knockback(seb: StoneEyeBug, player: Node2D) -> void:
	## 击退玩家（velocity，严禁 position）
	if "velocity" not in player:
		return
	var dir_x := signf(player.global_position.x - seb.global_position.x)
	# 无水平分量时默认向右推
	if dir_x == 0.0:
		dir_x = 1.0
	player.set("velocity", Vector2(dir_x * seb.knockback_strength, player.get("velocity").y))


func _finish_attack(seb: StoneEyeBug) -> void:
	seb.next_attack_end_ms = StoneEyeBug.now_ms() + int(seb.attack_cd * 1000.0)
	_phase = Phase.DONE


func interrupt(actor: Node, blackboard: Blackboard) -> void:
	var seb := actor as StoneEyeBug
	if seb != null:
		seb.velocity = Vector2.ZERO
	_phase = Phase.STOP
	super(actor, blackboard)
