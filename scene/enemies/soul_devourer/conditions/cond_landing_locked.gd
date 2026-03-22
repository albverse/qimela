extends ConditionLeaf
class_name CondSoulDevourerLandingLocked

## P1：着陆锁定期间（fall_loop → fall_down 序列），禁止任何行为插入。

func tick(actor: Node, _blackboard: Blackboard) -> int:
	var sd: SoulDevourer = actor as SoulDevourer
	if sd == null:
		return FAILURE
	if sd._landing_locked:
		return SUCCESS
	return FAILURE
