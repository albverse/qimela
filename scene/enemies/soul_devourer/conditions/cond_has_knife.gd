extends ConditionLeaf
class_name CondSoulDevourerHasKnife

## P7：持刀状态（has_knife/冲刺攻击序列）。

func tick(actor: Node, _blackboard: Blackboard) -> int:
	var sd: SoulDevourer = actor as SoulDevourer
	if sd == null:
		return FAILURE
	if sd._has_knife:
		return SUCCESS
	return FAILURE
