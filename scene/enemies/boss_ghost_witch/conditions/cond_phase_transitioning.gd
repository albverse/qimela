## 检查 Boss 是否正在变身
extends ConditionLeaf
class_name CondPhaseTransitioning

func tick(actor: Node, _blackboard: Blackboard) -> int:
	var boss: BossGhostWitch = actor as BossGhostWitch
	if boss == null:
		return FAILURE
	return SUCCESS if boss._phase_transitioning else FAILURE
