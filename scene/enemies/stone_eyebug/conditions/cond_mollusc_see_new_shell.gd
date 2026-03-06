extends ConditionLeaf
class_name CondMolluscSeeNewShell

## 检查软体虫是否能看到"新壳"（非 home_shell 的空壳），且入场动画已结束。
## 生成后无延迟，立即可触发回新壳行为。

func tick(actor: Node, _blackboard: Blackboard) -> int:
	var mollusc := actor as Mollusc
	if mollusc == null:
		return FAILURE
	# 入场动画未结束时不检测，避免刚生成就回壳
	if mollusc.spawn_enter_active:
		return FAILURE
	var shell := mollusc.find_new_shell()
	if shell != null:
		return SUCCESS
	return FAILURE
