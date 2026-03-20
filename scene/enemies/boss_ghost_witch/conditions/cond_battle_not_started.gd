extends ConditionLeaf
class_name CondBattleNotStarted

## 检查战斗是否尚未开始

func tick(actor: Node, _bb: Blackboard) -> int:
	var boss: BossGhostWitch = actor as BossGhostWitch
	return SUCCESS if boss != null and not boss._battle_started else FAILURE
