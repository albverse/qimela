extends ConditionLeaf
class_name CondSEBAttackReady

## 检查石眼虫攻击冷却是否结束（自管理，不依赖 CooldownDecorator）。

func tick(actor: Node, _blackboard: Blackboard) -> int:
	var seb := actor as StoneEyeBug
	if seb == null:
		return FAILURE
	if StoneEyeBug.now_ms() >= seb.next_attack_end_ms:
		return SUCCESS
	return FAILURE
