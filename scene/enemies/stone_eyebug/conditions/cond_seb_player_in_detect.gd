extends ConditionLeaf
class_name CondSEBPlayerInDetect

## 检查玩家是否在石眼虫检测范围内（自给自足感知，不依赖 blackboard）。

func tick(actor: Node, _blackboard: Blackboard) -> int:
	var seb := actor as StoneEyeBug
	if seb == null:
		return FAILURE
	if seb.is_player_in_detect_area():
		return SUCCESS
	return FAILURE
