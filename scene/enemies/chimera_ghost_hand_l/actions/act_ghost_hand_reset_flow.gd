extends ActionLeaf
class_name ActGhostHandResetFlow

## 幽灵手重置流程：vanish → 传送到玩家附近 → appear → idle_float → 清除标记。

enum Phase { VANISH, TELEPORT, APPEAR, DONE }

var _phase: int = Phase.VANISH


func before_run(actor: Node, _blackboard: Blackboard) -> void:
	var ghost := actor as ChimeraGhostHandL
	if ghost == null:
		return
	_phase = Phase.VANISH
	ghost.velocity = Vector2.ZERO
	ghost.anim_play(&"vanish", false, true)


func tick(actor: Node, _blackboard: Blackboard) -> int:
	var ghost := actor as ChimeraGhostHandL
	if ghost == null:
		return FAILURE

	match _phase:
		Phase.VANISH:
			return _tick_vanish(ghost)
		Phase.TELEPORT:
			return _tick_teleport(ghost)
		Phase.APPEAR:
			return _tick_appear(ghost)
		Phase.DONE:
			return SUCCESS
	return RUNNING


func _tick_vanish(ghost: ChimeraGhostHandL) -> int:
	if ghost.anim_is_finished(&"vanish"):
		_phase = Phase.TELEPORT
	return RUNNING


func _tick_teleport(ghost: ChimeraGhostHandL) -> int:
	ghost.teleport_to_player_side()
	_phase = Phase.APPEAR
	ghost.anim_play(&"appear", false, true)
	return RUNNING


func _tick_appear(ghost: ChimeraGhostHandL) -> int:
	if ghost.anim_is_finished(&"appear"):
		_phase = Phase.DONE
		# 清除重置标记
		ghost.took_damage = false
		ghost.over_chain_limit = false
		ghost.detached_reset_pending = false
		ghost.anim_play(&"idle_float", true, true)
		return SUCCESS
	return RUNNING


func interrupt(actor: Node, blackboard: Blackboard) -> void:
	var ghost := actor as ChimeraGhostHandL
	if ghost != null:
		ghost.velocity = Vector2.ZERO
	_phase = Phase.VANISH
	super(actor, blackboard)
