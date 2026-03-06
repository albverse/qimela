extends ConditionLeaf
class_name CondMolluscPlayerInRange

## 检查玩家是否在软体虫攻击范围内（自给自足感知）。

func tick(actor: Node, _blackboard: Blackboard) -> int:
	var mollusc := actor as Mollusc
	if mollusc == null:
		return FAILURE
	if mollusc.is_player_in_attack_range():
		return SUCCESS
	return FAILURE
