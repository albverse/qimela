extends ConditionLeaf
class_name CondMolluscPlayerNear

## 检查玩家是否在软体虫威胁距离内（threat_dist），用于决定是否需要逃跑。
## 距离 <= threat_dist 返回 SUCCESS（需要逃跑），否则 FAILURE（可以 idle）。

func tick(actor: Node, _blackboard: Blackboard) -> int:
	var mollusc := actor as Mollusc
	if mollusc == null:
		return FAILURE
	# 回壳承诺期间：忽略玩家威胁触发的逃跑分支，优先完成回壳。
	if mollusc.is_shell_return_committed():
		return FAILURE
	# 玩家在威胁半径内：立刻逃跑。
	if mollusc.is_player_near_threat():
		return SUCCESS
	# 玩家离开后仍允许把当前“逃跑段”跑完，避免 escape_dist/escape_speed 体感失效。
	if mollusc.escape_remaining > 0.0:
		return SUCCESS
	return FAILURE
