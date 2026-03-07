extends ConditionLeaf
class_name CondNNSModeIs

## 检查 ChimeraNunSnake.mode 是否等于指定值。
## 在 Inspector 中将 target_mode 设为 ChimeraNunSnake.Mode 枚举整数。

@export var target_mode: int = 0
## 要匹配的 mode 值（ChimeraNunSnake.Mode 枚举整数）

func tick(actor: Node, _blackboard: Blackboard) -> int:
	var nns := actor as ChimeraNunSnake
	if nns == null:
		return FAILURE
	if nns.mode == target_mode:
		return SUCCESS
	return FAILURE
