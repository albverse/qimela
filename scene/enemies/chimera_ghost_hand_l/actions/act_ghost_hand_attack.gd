extends ActionLeaf
class_name ActGhostHandAttack

## 幽灵手攻击：冻结操控 → 播 attack 动画 → 命中检测 → 解冻操控 → 清除请求。
## 命中规则：
##   - StoneMaskBirdFaceBullet → bullet.velocity.y *= -1
##   - StoneEyeBug（带壳态 NORMAL）→ 触发弹翻
##   - 其他实体 → 普通伤害

enum Phase { FREEZE, ATTACK_ANIM, UNFREEZE, DONE }

var _phase: int = Phase.FREEZE


func before_run(actor: Node, _blackboard: Blackboard) -> void:
	var ghost := actor as ChimeraGhostHandL
	if ghost == null:
		return
	_phase = Phase.FREEZE
	ghost.velocity = Vector2.ZERO


func tick(actor: Node, _blackboard: Blackboard) -> int:
	var ghost := actor as ChimeraGhostHandL
	if ghost == null:
		return FAILURE

	match _phase:
		Phase.FREEZE:
			return _tick_freeze(ghost)
		Phase.ATTACK_ANIM:
			return _tick_attack(ghost)
		Phase.UNFREEZE:
			return _tick_unfreeze(ghost)
		Phase.DONE:
			return SUCCESS
	return RUNNING


func _tick_freeze(ghost: ChimeraGhostHandL) -> int:
	# 冻结玩家操控输入
	var player := ghost.get_player_node()
	if player != null and player.has_method("set_external_control_frozen"):
		player.call("set_external_control_frozen", true)
	ghost.control_input_frozen = true
	_phase = Phase.ATTACK_ANIM
	ghost.anim_play(&"attack", false, false)
	ghost.atk_hit_window_open = true  # 命中窗口开（hit_on 等效）
	return RUNNING


func _tick_attack(ghost: ChimeraGhostHandL) -> int:
	if ghost.anim_is_finished(&"attack"):
		ghost.atk_hit_window_open = false  # 命中窗口关（hit_off 等效）
		# 命中检测（hit_on/off 事件在 Mock 中以动画结束点代替）
		ghost.resolve_hit_on_targets()
		_phase = Phase.UNFREEZE
	return RUNNING


func _tick_unfreeze(ghost: ChimeraGhostHandL) -> int:
	# 解冻玩家操控
	var player := ghost.get_player_node()
	if player != null and player.has_method("set_external_control_frozen"):
		player.call("set_external_control_frozen", false)
	ghost.control_input_frozen = false
	ghost.attack_requested = false
	_phase = Phase.DONE
	return SUCCESS


func interrupt(actor: Node, blackboard: Blackboard) -> void:
	var ghost := actor as ChimeraGhostHandL
	if ghost != null:
		# 解冻确保不留下冻结状态
		var player := ghost.get_player_node()
		if player != null and player.has_method("set_external_control_frozen"):
			player.call("set_external_control_frozen", false)
		ghost.control_input_frozen = false
		ghost.velocity = Vector2.ZERO
		ghost.force_close_hit_windows()  # 强制关命中窗口（受伤重置打断攻击时）
	_phase = Phase.FREEZE
	super(actor, blackboard)
