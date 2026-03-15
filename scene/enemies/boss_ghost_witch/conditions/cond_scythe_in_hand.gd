extends ConditionLeaf
class_name CondScytheInHand

## 检查镰刀是否在手中

func tick(actor: Node, _bb: Blackboard) -> int:
	var boss: BossGhostWitch = actor as BossGhostWitch
	if boss == null:
		return FAILURE
	return SUCCESS if boss._scythe_in_hand else FAILURE
