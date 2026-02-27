extends ConditionLeaf
class_name CondAttackTimeExpired

## 检查飞行攻击时间是否已到期（attack_until_sec）。
## 用于判断是否应该回巢。

func tick(actor: Node, _blackboard: Blackboard) -> int:
	var bird := actor as StoneMaskBird
	if bird == null:
		return FAILURE
	var now := StoneMaskBird.now_sec()
	if now >= bird.attack_until_sec:
		return SUCCESS
	return FAILURE
