extends ConditionLeaf
class_name CondHasPetrifiedTarget

## 检测场内是否存在石化玩家。
## 自给自足感知，不依赖其他分支的 blackboard 写入。

func tick(actor: Node, _blackboard: Blackboard) -> int:
	var snake: ChimeraNunSnake = actor as ChimeraNunSnake
	if snake == null:
		return FAILURE
	# WEAK/STUN 状态不进入追击
	if snake.mode == ChimeraNunSnake.Mode.WEAK or snake.mode == ChimeraNunSnake.Mode.STUN:
		return FAILURE
	var petrified: Node2D = snake.detect_petrified_player()
	if petrified != null:
		snake.petrified_target_node = petrified
		return SUCCESS
	snake.petrified_target_node = null
	return FAILURE
