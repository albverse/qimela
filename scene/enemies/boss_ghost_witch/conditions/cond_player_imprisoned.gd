## 检查玩家是否被地狱之手禁锢
extends ConditionLeaf
class_name CondPlayerImprisoned

func tick(actor: Node, _bb: Blackboard) -> int:
	var boss := actor as BossGhostWitch
	if boss == null:
		return FAILURE
	return SUCCESS if boss._player_imprisoned else FAILURE
