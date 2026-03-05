extends ConditionLeaf
class_name CondSEBAttackedFlipped

## 检查石眼虫弹翻中是否被攻击（→ 触发逃跑分裂）。

func tick(actor: Node, _blackboard: Blackboard) -> int:
	var seb := actor as StoneEyeBug
	if seb == null:
		return FAILURE
	if seb.was_attacked_while_flipped:
		return SUCCESS
	return FAILURE
