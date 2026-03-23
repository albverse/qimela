extends ConditionLeaf
class_name CondSoulDevourerWandering

## P11：idle 超过 1 秒后进入闲逛。

func tick(actor: Node, _blackboard: Blackboard) -> int:
	var sd: SoulDevourer = actor as SoulDevourer
	if sd == null:
		return FAILURE
	if not sd._is_wandering:
		return FAILURE
	if sd._is_floating_invisible or sd._forced_invisible or sd._has_knife:
		return FAILURE
	return SUCCESS
