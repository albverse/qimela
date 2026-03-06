extends ConditionLeaf
class_name CondMolluscPlayerInRange

## 检查玩家是否在软体虫攻击范围内（自给自足感知）。

func tick(actor: Node, _blackboard: Blackboard) -> int:
	var mollusc := actor as Mollusc
	if mollusc == null:
		return FAILURE
	# 回壳承诺期间禁止攻击分支抢占（与“忽略玩家逃跑检测”语义一致）。
	if mollusc.is_shell_return_committed():
		return FAILURE
	if mollusc.is_player_in_attack_range():
		return SUCCESS
	return FAILURE
