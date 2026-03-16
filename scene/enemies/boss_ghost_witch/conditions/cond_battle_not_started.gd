## 检查 Boss 战是否尚未开始
extends ConditionLeaf
class_name CondBattleNotStarted

func tick(actor: Node, _bb: Blackboard) -> int:
	var boss := actor as BossGhostWitch
	return SUCCESS if boss != null and not boss._battle_started else FAILURE
