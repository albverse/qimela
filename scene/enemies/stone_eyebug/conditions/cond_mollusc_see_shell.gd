extends ConditionLeaf
class_name CondMolluscSeeShell

## 检查软体虫是否能看到空壳（group: stoneeyebug_shell_empty），并满足回壳时间门控。
## 纯自感知条件：只返回 SUCCESS/FAILURE，不写 blackboard。

func tick(actor: Node, _blackboard: Blackboard) -> int:
	var mollusc := actor as Mollusc
	if mollusc == null:
		return FAILURE
	if not mollusc.is_shell_return_window_open():
		return FAILURE
	var shell := mollusc.find_empty_shell()
	if shell != null:
		return SUCCESS
	return FAILURE
