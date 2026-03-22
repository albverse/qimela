extends ConditionLeaf
class_name CondSoulDevourerMerging

## P3：合体移动中（向 partner 靠拢）。

func tick(actor: Node, _blackboard: Blackboard) -> int:
	var sd: SoulDevourer = actor as SoulDevourer
	if sd == null:
		return FAILURE
	if sd._merging:
		return SUCCESS
	return FAILURE
