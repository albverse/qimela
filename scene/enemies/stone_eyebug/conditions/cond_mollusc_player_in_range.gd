extends ConditionLeaf
class_name CondMolluscPlayerInRange

## 检查玩家是否在软体虫攻击范围内（自给自足感知）。

func tick(actor: Node, blackboard: Blackboard) -> int:
	var mollusc := actor as Mollusc
	if mollusc == null:
		return FAILURE
	if mollusc.is_player_in_attack_range():
		var player := mollusc.get_player()
		if player != null:
			blackboard.set_value("player", player)
		return SUCCESS
	blackboard.erase_value("player")
	return FAILURE
