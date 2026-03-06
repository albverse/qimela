extends ConditionLeaf
class_name CondMolluscIdleHitEscape

## Idle 状态下若刚受到攻击，则触发应激反向逃跑。
## 注意：在 SequenceReactive 中不能“消费即清空”，否则下一帧条件会失败并打断逃跑。

func tick(actor: Node, _blackboard: Blackboard) -> int:
	var mollusc := actor as Mollusc
	if mollusc == null:
		return FAILURE
	if mollusc.has_idle_hit_escape_request():
		return SUCCESS
	return FAILURE
