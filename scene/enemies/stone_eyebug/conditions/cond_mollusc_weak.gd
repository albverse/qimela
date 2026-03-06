extends ConditionLeaf
class_name CondMolluscWeak

## 检查软体虫是否处于虚弱眩晕状态（hp <= weak_hp，hp_locked = true）。

func tick(actor: Node, _blackboard: Blackboard) -> int:
	var mollusc := actor as Mollusc
	if mollusc == null:
		return FAILURE
	return SUCCESS if (mollusc.weak or mollusc.lightflower_weak_stun_active) else FAILURE
