## 检查婴儿石像是否在怀中
extends ConditionLeaf
class_name CondBabyInHug

func tick(actor: Node, _bb: Blackboard) -> int:
	var boss := actor as BossGhostWitch
	return SUCCESS if boss != null and boss.baby_state == BossGhostWitch.BabyState.IN_HUG else FAILURE
