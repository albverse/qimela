extends ConditionLeaf
class_name CondMolluscSeeShell

## 检查软体虫是否能看到空壳（group: stoneeyebug_shell_empty）。
## 自给自足感知，顺手写入 blackboard["empty_shell"]。

func tick(actor: Node, blackboard: Blackboard) -> int:
	var mollusc := actor as Mollusc
	if mollusc == null:
		return FAILURE
	var shell := mollusc.find_empty_shell()
	if shell != null:
		blackboard.set_value("empty_shell", shell)
		return SUCCESS
	blackboard.erase_value("empty_shell")
	return FAILURE
