extends ConditionLeaf
class_name CondSoulDevourerFloatingInvisible

## P4：漂浮隐身状态（包含强制隐身）。

func tick(actor: Node, _blackboard: Blackboard) -> int:
	var sd: SoulDevourer = actor as SoulDevourer
	if sd == null:
		return FAILURE
	if sd._is_floating_invisible:
		return SUCCESS
	return FAILURE
