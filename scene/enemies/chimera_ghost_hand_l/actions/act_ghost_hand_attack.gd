extends ActionLeaf
class_name ActGhostHandAttack

## 幽灵手攻击：播 attack 动画 → 命中检测 → 清除请求。
## 注意：玩家移动冻结由 ActGhostHandLinkedMove（链接态常驻）统一维护，
## 本动作不再改动玩家冻结状态，避免攻击期间出现一帧可移动。
## 命中规则：
##   - StoneMaskBirdFaceBullet → bullet.reflect()
##   - StoneEyeBug → apply_hit（weapon_id=chimera_ghost_hand_l，内部触发弹翻）
##   - 其他实体 → 普通伤害
##
## 命中时机依赖 Spine 事件：hit_on / attack_done。
## Mock 兜底：动画结束点作为命中时机。

enum Phase { ATTACK_ANIM, DONE }

var _phase: int = Phase.ATTACK_ANIM
var _hit_resolved: bool = false


func before_run(actor: Node, _blackboard: Blackboard) -> void:
	var ghost := actor as ChimeraGhostHandL
	if ghost == null:
		return
	_phase = Phase.ATTACK_ANIM
	ghost.velocity = Vector2.ZERO
	_hit_resolved = false
	ghost.ev_hit_on = false
	ghost.ev_attack_done = false
	ghost.anim_play(&"attack", false, false)


func tick(actor: Node, _blackboard: Blackboard) -> int:
	var ghost := actor as ChimeraGhostHandL
	if ghost == null:
		return FAILURE

	match _phase:
		Phase.ATTACK_ANIM:
			return _tick_attack(ghost)
		Phase.DONE:
			return SUCCESS
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
		ghost.attack_requested = false
		_phase = Phase.DONE
	return RUNNING


func interrupt(actor: Node, blackboard: Blackboard) -> void:
	var ghost := actor as ChimeraGhostHandL
	if ghost != null:
		ghost.velocity = Vector2.ZERO
		ghost.attack_requested = false
		ghost.force_close_hit_windows()  # 强制关命中窗口（受伤重置打断攻击时）
	_phase = Phase.ATTACK_ANIM
	super(actor, blackboard)
