extends ConditionLeaf
class_name CondIsPhase
@export var phase: int = 1
func tick(actor: Node, _blackboard: Blackboard) -> int:
	var boss := actor as BossGhostWitch
	if boss == null:
		return FAILURE
	return SUCCESS if boss.current_phase == phase else FAILURE
