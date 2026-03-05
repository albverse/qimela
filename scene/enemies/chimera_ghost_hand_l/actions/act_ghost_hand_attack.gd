extends ActionLeaf
class_name ActGhostHandAttack

## 幽灵手攻击：冻结操控 → 播 attack 动画 → 命中检测 → 解冻操控 → 清除请求。
## 命中规则：
##   - StoneMaskBirdFaceBullet → bullet.reflect()
##   - StoneEyeBug → apply_hit（weapon_id=chimera_ghost_hand_l，内部触发弹翻）
##   - 其他实体 → 普通伤害
##
## 命中时机依赖 Spine 事件：hit_on / attack_done。
## Mock 兜底：动画结束点作为命中时机。

enum Phase { FREEZE, ATTACK_ANIM, UNFREEZE, DONE }

var _phase: int = Phase.FREEZE
var _hit_resolved: bool = false


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
	var player := ghost.get_player_node()
	if player != null and player.has_method("set_external_control_frozen"):
		player.call("set_external_control_frozen", true)
	ghost.control_input_frozen = true
	_phase = Phase.ATTACK_ANIM
	_hit_resolved = false
	ghost.ev_hit_on = false
	ghost.ev_attack_done = false
	ghost.anim_play(&"attack", false, false)
	return RUNNING


func _tick_attack(ghost: ChimeraGhostHandL) -> int:
	# Spine hit_on：命中窗口开，立即执行命中检测
	if not _hit_resolved and ghost.ev_hit_on:
		ghost.ev_hit_on = false
		_hit_resolved = true
		ghost.resolve_hit_on_targets()
	# Spine attack_done 或 Mock anim_finished：动画结束，推进到解冻
	if ghost.ev_attack_done or ghost.anim_is_finished(&"attack"):
		ghost.ev_attack_done = false
		# Mock 兜底：若 Spine 未触发 hit_on，在动画结束点执行命中检测
		if not _hit_resolved:
			ghost.resolve_hit_on_targets()
		_phase = Phase.UNFREEZE
	return RUNNING


func _tick_unfreeze(ghost: ChimeraGhostHandL) -> int:
	# 攻击结束后保持与链接状态一致的冻结策略：
	# 仍链接则继续冻结，断链才解冻。
	ghost.call("_sync_player_control_freeze")
	ghost.control_input_frozen = false
	ghost.attack_requested = false
	_phase = Phase.DONE
	return SUCCESS


func interrupt(actor: Node, blackboard: Blackboard) -> void:
	var ghost := actor as ChimeraGhostHandL
	if ghost != null:
		# 打断时同样按当前链接状态同步冻结。
		ghost.call("_sync_player_control_freeze")
		ghost.control_input_frozen = false
		ghost.velocity = Vector2.ZERO
		ghost.force_close_hit_windows()  # 强制关命中窗口（受伤重置打断攻击时）
	_phase = Phase.FREEZE
	super(actor, blackboard)
