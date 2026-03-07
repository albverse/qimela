extends ConditionLeaf
class_name CondNNSDetectTarget

## 检查是否检测到玩家或攻击目标（自给自足感知）。
## 检测到时写入 blackboard["target_node"]。

func tick(actor: Node, blackboard: Blackboard) -> int:
	var nns := actor as ChimeraNunSnake
	if nns == null:
		return FAILURE

	var target: Node2D = nns.get_player()
	if target == null:
		blackboard.erase_value("target_node")
		return FAILURE

	blackboard.set_value("target_node", target)
	return SUCCESS
