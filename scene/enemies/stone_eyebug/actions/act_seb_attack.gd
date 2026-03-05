extends ActionLeaf
class_name ActSEBAttack

## 石眼虫攻击序列：停步 → 朝向玩家 → attack_stone（石化）→ attack_lick（击退）→ 设冷却。
## 攻击冷却在此 ActionLeaf 内自管理（写入 seb.next_attack_end_ms），
## 不使用 CooldownDecorator（会被 SelectorReactive interrupt 重置）。
##
## 命中时机依赖 Spine 事件：atk1_hit_on / atk1_hit_off / atk2_hit_on / atk2_hit_off。
## Mock 兜底：动画结束点作为命中时机。

enum Phase { STOP, ATTACK_STONE, ATTACK_LICK, DONE }

var _phase: int = Phase.STOP
var _atk1_hit_applied: bool = false
var _atk2_hit_applied: bool = false


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

	var player: Node2D = seb.get_player()

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
	if player != null and is_instance_valid(player):
		seb.facing = 1 if player.global_position.x >= seb.global_position.x else -1
	_phase = Phase.ATTACK_STONE
	_atk1_hit_applied = false
	seb.ev_atk1_hit_on = false
	seb.ev_atk1_hit_off = false
	seb.anim_play(&"attack_stone", false, false)
	return RUNNING


func _tick_attack_stone(seb: StoneEyeBug, player: Node2D) -> int:
	# Spine atk1_hit_on：命中窗口开，立即施加石化
	if not _atk1_hit_applied and seb.ev_atk1_hit_on:
		seb.ev_atk1_hit_on = false
		_atk1_hit_applied = true
		if seb.is_player_in_detect_area() and player != null and is_instance_valid(player):
			_apply_stone_stun(seb, player)
	# Spine atk1_hit_off 或 Mock anim_finished：命中窗口关，推进阶段
	if seb.ev_atk1_hit_off or seb.anim_is_finished(&"attack_stone"):
		seb.ev_atk1_hit_off = false
		# Mock 兜底：若 Spine 未开窗，在动画结束点应用伤害
		if not _atk1_hit_applied:
			if seb.is_player_in_detect_area() and player != null and is_instance_valid(player):
				_apply_stone_stun(seb, player)
		if seb.is_player_in_detect_area():
			_phase = Phase.ATTACK_LICK
			_atk2_hit_applied = false
			seb.ev_atk2_hit_on = false
			seb.ev_atk2_hit_off = false
			seb.anim_play(&"attack_lick", false, false)
		else:
			_finish_attack(seb)
	return RUNNING


func _apply_stone_stun(seb: StoneEyeBug, player: Node2D) -> void:
	if player.has_method("apply_stone_stun"):
		player.call("apply_stone_stun", seb.player_stone_stun)


func _tick_attack_lick(seb: StoneEyeBug, player: Node2D) -> int:
	# Spine atk2_hit_on：命中窗口开，立即施加击退
	if not _atk2_hit_applied and seb.ev_atk2_hit_on:
		seb.ev_atk2_hit_on = false
		_atk2_hit_applied = true
		if seb.is_player_in_detect_area() and player != null and is_instance_valid(player):
			_apply_lick_knockback(seb, player)
	# Spine atk2_hit_off 或 Mock anim_finished：命中窗口关，结束攻击
	if seb.ev_atk2_hit_off or seb.anim_is_finished(&"attack_lick"):
		seb.ev_atk2_hit_off = false
		if not _atk2_hit_applied:
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
	# 仅在“进入缩壳后解锁”的窗口内触发一次攻击；结束后关闭，避免普通移动态持续攻击。
	seb.attack_enabled_after_player_retreat = false
	_phase = Phase.DONE


func interrupt(actor: Node, blackboard: Blackboard) -> void:
	var seb := actor as StoneEyeBug
	if seb != null:
		seb.velocity = Vector2.ZERO
		seb.force_close_hit_windows()  # 强制关命中窗口（雷击/弹翻打断时防止判定残留）
	_phase = Phase.STOP
	super(actor, blackboard)
