extends ConditionLeaf
class_name CondMolluscIdleHitEscape

## Idle 状态下若刚受到攻击，则立刻触发一次反向逃跑。

func tick(actor: Node, _blackboard: Blackboard) -> int:
	var mollusc := actor as Mollusc
	if mollusc == null:
		return FAILURE
	if mollusc.consume_idle_hit_escape_request():
		return SUCCESS
	return FAILURE
