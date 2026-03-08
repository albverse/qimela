extends ConditionLeaf
class_name CondNunSnakeIsWeakOrStun

## 检查修女蛇是否处于 WEAK 或 STUN 状态。

func tick(actor: Node, _blackboard: Blackboard) -> int:
	var snake: ChimeraNunSnake = actor as ChimeraNunSnake
	if snake == null:
		return FAILURE
	if snake.mode == ChimeraNunSnake.Mode.WEAK or snake.mode == ChimeraNunSnake.Mode.STUN:
		return SUCCESS
	return FAILURE
