extends ConditionLeaf
class_name CondAllP3SkillsBlocked
func tick(actor: Node, _bb: Blackboard) -> int:
	var boss := actor as BossGhostWitch
	if boss == null:
		return FAILURE
	return SUCCESS if boss._scythe_in_hand else FAILURE
