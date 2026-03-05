extends ConditionLeaf
class_name CondGhostHandAttackRequested

## 检查幽灵手是否有攻击请求（玩家输入层写入 attack_requested）。

func tick(actor: Node, _blackboard: Blackboard) -> int:
	var ghost := actor as ChimeraGhostHandL
	if ghost == null:
		return FAILURE
	if ghost.attack_requested:
		return SUCCESS
	return FAILURE
