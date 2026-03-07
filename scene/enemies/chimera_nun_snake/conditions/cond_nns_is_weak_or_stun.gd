extends ConditionLeaf
class_name CondNNSIsWeakOrStun

## 检查 ChimeraNunSnake 是否处于 WEAK 或 STUN 状态。

func tick(actor: Node, _blackboard: Blackboard) -> int:
	var nns := actor as ChimeraNunSnake
	if nns == null:
		return FAILURE
	if nns.mode == ChimeraNunSnake.Mode.WEAK or nns.mode == ChimeraNunSnake.Mode.STUN:
		return SUCCESS
	return FAILURE
