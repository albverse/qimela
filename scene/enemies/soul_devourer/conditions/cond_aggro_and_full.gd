extends ConditionLeaf
class_name CondSoulDevourerAggroAndFull

## P8：aggro 模式下处于 full 状态（已吞食幽灵）。
## CD/距离检查移至 action 内部处理，条件仅判断 aggro + full。

func tick(actor: Node, _blackboard: Blackboard) -> int:
	var sd: SoulDevourer = actor as SoulDevourer
	if sd == null:
		return FAILURE
	if not sd._aggro_mode:
		return FAILURE
	if not sd._is_full:
		return FAILURE
	return SUCCESS
