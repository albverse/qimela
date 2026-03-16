## 检查 Boss 当前是否处于指定阶段
extends ConditionLeaf
class_name CondIsPhase

@export var phase: int = 1

func tick(actor: Node, _blackboard: Blackboard) -> int:
	var boss: BossGhostWitch = actor as BossGhostWitch
	if boss == null:
		return FAILURE
	return SUCCESS if boss.current_phase == phase else FAILURE
