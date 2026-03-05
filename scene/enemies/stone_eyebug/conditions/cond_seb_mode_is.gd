extends ConditionLeaf
class_name CondSEBModeIs

## 检查 StoneEyeBug.mode 是否等于指定值。
## 在 Inspector 中将 target_mode 设为 StoneEyeBug.Mode 枚举值。

@export var target_mode: int = 0
## 要匹配的 mode 值（StoneEyeBug.Mode 枚举整数）

func tick(actor: Node, _blackboard: Blackboard) -> int:
	var seb := actor as StoneEyeBug
	if seb == null:
		return FAILURE
	if seb.mode == target_mode:
		return SUCCESS
	return FAILURE
