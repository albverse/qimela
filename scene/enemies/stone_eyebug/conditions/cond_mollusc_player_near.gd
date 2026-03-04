extends ConditionLeaf
class_name CondMolluscPlayerNear

## 检查玩家是否在软体虫威胁距离内（threat_dist），用于决定是否需要逃跑。
## 距离 <= threat_dist 返回 SUCCESS（需要逃跑），否则 FAILURE（可以 idle）。

func tick(actor: Node, _blackboard: Blackboard) -> int:
	var mollusc := actor as Mollusc
	if mollusc == null:
		return FAILURE
	var player := mollusc.get_player()
	if player == null:
		return FAILURE
	var dist := mollusc.global_position.distance_to(player.global_position)
	return SUCCESS if dist <= mollusc.threat_dist else FAILURE
