extends ConditionLeaf
class_name CondSEBPlayerInDetect

## 检查玩家是否在石眼虫检测范围内（自给自足感知，不依赖 blackboard）。

func tick(actor: Node, blackboard: Blackboard) -> int:
	var seb := actor as StoneEyeBug
	if seb == null:
		return FAILURE
	if seb.is_player_in_detect_area():
		var player := seb.get_player()
		if player != null:
			blackboard.set_value("player", player)
		return SUCCESS
	return FAILURE
