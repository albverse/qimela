extends ConditionLeaf
class_name CondMolluscSpawnEntering

## Mollusc 刚生成时，先执行 enter 入场动画，完成后再进入常规行为。

func tick(actor: Node, _blackboard: Blackboard) -> int:
	var mollusc := actor as Mollusc
	if mollusc == null:
		return FAILURE
	return SUCCESS if mollusc.spawn_enter_active else FAILURE
