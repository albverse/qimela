extends ConditionLeaf
class_name CondWGPlayerInDetect

## 检查玩家是否在幽灵检测范围内（不检查显隐，隐身也追）。

func tick(actor: Node, _blackboard: Blackboard) -> int:
	var ghost: WanderingGhost = actor as WanderingGhost
	if ghost == null:
		return FAILURE
	if ghost.is_player_in_detect_area():
		return SUCCESS
	return FAILURE
