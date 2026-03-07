extends ConditionLeaf
class_name CondNNSHasPetrifiedTarget

## 检查场景中是否存在石化玩家。
## 自给自足：直接查询 "player" 组，不依赖 blackboard 脏数据。

func tick(actor: Node, blackboard: Blackboard) -> int:
	var nns := actor as ChimeraNunSnake
	if nns == null:
		return FAILURE

	# 不可中断状态下不进入石化追击
	if nns.mode == ChimeraNunSnake.Mode.WEAK or nns.mode == ChimeraNunSnake.Mode.STUN:
		return FAILURE

	var petrified: Node2D = nns.get_petrified_player()
	if petrified == null:
		blackboard.erase_value("petrified_target_node")
		return FAILURE

	blackboard.set_value("petrified_target_node", petrified)
	return SUCCESS
