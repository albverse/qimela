extends ConditionLeaf
class_name CondWGDyingOrHunted

## 检查幽灵是否正在死亡或被吞食。

func tick(actor: Node, _blackboard: Blackboard) -> int:
	var ghost: WanderingGhost = actor as WanderingGhost
	if ghost == null:
		return FAILURE
	if ghost._dying or ghost._being_hunted:
		return SUCCESS
	return FAILURE
