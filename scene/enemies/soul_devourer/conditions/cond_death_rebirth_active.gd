extends ConditionLeaf
class_name CondSoulDevourerDeathRebirthActive

## P0：death-rebirth 流程激活时占据最高优先级，锁死其他行为。

func tick(actor: Node, _blackboard: Blackboard) -> int:
	var sd: SoulDevourer = actor as SoulDevourer
	if sd == null:
		return FAILURE
	if sd._death_rebirth_started:
		return SUCCESS
	return FAILURE
