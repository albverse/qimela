extends ConditionLeaf
class_name CondMolluscSeeNewShell

## 检查软体虫是否能看到非 home_shell 的新空壳（group: stoneeyebug_shell_empty）。
## 无时间门控：生成后立即检测，优先于 idle 回壳。
## 纯自感知条件：只返回 SUCCESS/FAILURE，不写 blackboard。

func tick(actor: Node, _blackboard: Blackboard) -> int:
	var mollusc := actor as Mollusc
	if mollusc == null:
		return FAILURE
	var shell := mollusc.find_new_shell()
	if shell != null:
		return SUCCESS
	return FAILURE
