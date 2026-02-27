extends ConditionLeaf
class_name CondModeIs

## 检查 StoneMaskBird.mode 是否等于指定值。
## 在 Inspector 中设置 target_mode 为 StoneMaskBird.Mode 枚举值。

@export var target_mode: int = 0
## 要匹配的 mode 值（对应 StoneMaskBird.Mode 枚举）

func tick(actor: Node, _blackboard: Blackboard) -> int:
	var bird := actor as StoneMaskBird
	if bird == null:
		return FAILURE
	if bird.mode == target_mode:
		return SUCCESS
	return FAILURE
