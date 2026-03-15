extends ConditionLeaf
class_name CondPlayerImprisoned

## 检查玩家是否被禁锢

func tick(actor: Node, _bb: Blackboard) -> int:
	var boss: BossGhostWitch = actor as BossGhostWitch
	if boss == null:
		return FAILURE
	return SUCCESS if boss._player_imprisoned else FAILURE
