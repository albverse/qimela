extends ConditionLeaf
class_name CondNunSnakeDetectTarget

## 检测玩家或 enemy_attack_target 是否在感知范围内。
## 自给自足感知，不依赖其他分支的 blackboard 写入。

func tick(actor: Node, blackboard: Blackboard) -> int:
	var snake: ChimeraNunSnake = actor as ChimeraNunSnake
	if snake == null:
		return FAILURE
	var target: Node2D = snake.detect_player_in_range(snake.detect_player_radius)
	if target != null:
		blackboard.set_value("target_node", target)
		return SUCCESS
	blackboard.erase_value("target_node")
	return FAILURE
