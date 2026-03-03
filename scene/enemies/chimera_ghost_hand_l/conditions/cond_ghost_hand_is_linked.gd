extends ConditionLeaf
class_name CondGhostHandIsLinked

## 检查幽灵手是否被链接。

func tick(actor: Node, _blackboard: Blackboard) -> int:
	var ghost := actor as ChimeraGhostHandL
	if ghost == null:
		return FAILURE
	if ghost.is_linked():
		return SUCCESS
	return FAILURE
