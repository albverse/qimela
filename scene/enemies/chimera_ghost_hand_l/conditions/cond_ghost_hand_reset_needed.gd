extends ConditionLeaf
class_name CondGhostHandResetNeeded

## 检查幽灵手奇美拉是否需要重置（受到伤害 or 超出链距离）。

func tick(actor: Node, _blackboard: Blackboard) -> int:
	var ghost := actor as ChimeraGhostHandL
	if ghost == null:
		return FAILURE
	if ghost.took_damage or ghost.over_chain_limit or ghost.detached_reset_pending:
		return SUCCESS
	return FAILURE
