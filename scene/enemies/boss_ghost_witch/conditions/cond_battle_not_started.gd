extends ConditionLeaf
class_name CondBattleNotStarted

func tick(actor: Node, _blackboard: Blackboard) -> int:
	var boss := actor as BossGhostWitch
	if boss == null:
		return FAILURE
	return SUCCESS if not boss._battle_started else FAILURE
