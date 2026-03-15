extends ConditionLeaf
class_name CondBabyNotInHug

## 检查婴儿石像是否不在怀中

func tick(actor: Node, _bb: Blackboard) -> int:
	var boss: BossGhostWitch = actor as BossGhostWitch
	return SUCCESS if boss != null and boss.baby_state != BossGhostWitch.BabyState.IN_HUG else FAILURE
