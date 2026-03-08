extends ConditionLeaf
class_name CondNunSnakeModeIs

## 检查 ChimeraNunSnake.mode 是否等于指定值。

@export var target_mode: int = 0
## 要匹配的 mode 值（对应 ChimeraNunSnake.Mode 枚举）

func tick(actor: Node, _blackboard: Blackboard) -> int:
	var snake: ChimeraNunSnake = actor as ChimeraNunSnake
	if snake == null:
		return FAILURE
	if snake.mode == target_mode:
		return SUCCESS
	return FAILURE
