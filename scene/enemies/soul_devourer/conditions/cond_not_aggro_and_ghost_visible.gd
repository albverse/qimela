extends ConditionLeaf
class_name CondSoulDevourerNotAggroAndGhostVisible

## P10：非 aggro 状态下被动猎杀（存在可见幽灵时自动趋近）。

func tick(actor: Node, _blackboard: Blackboard) -> int:
	var sd: SoulDevourer = actor as SoulDevourer
	if sd == null:
		return FAILURE
	# aggro 模式由更高优先级序列处理
	if sd._aggro_mode:
		return FAILURE
	if sd._is_full:
		return FAILURE
	var ghost: Node2D = sd._find_nearest_huntable_ghost()
	if ghost == null:
		return FAILURE
	return SUCCESS
