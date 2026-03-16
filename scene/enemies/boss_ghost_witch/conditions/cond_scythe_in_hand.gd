## 检查镰刀是否在手中（Phase 3 用）
extends ConditionLeaf
class_name CondScytheInHand

func tick(actor: Node, _bb: Blackboard) -> int:
	var boss := actor as BossGhostWitch
	if boss == null:
		return FAILURE
	return SUCCESS if boss._scythe_in_hand else FAILURE
