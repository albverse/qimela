extends ConditionLeaf
class_name CondSoulDevourerForceSeparate

## P2：双头犬分离后强制远离 partner。

func tick(actor: Node, _blackboard: Blackboard) -> int:
	var sd: SoulDevourer = actor as SoulDevourer
	if sd == null:
		return FAILURE
	if sd._force_separate:
		return SUCCESS
	return FAILURE
