extends ActionLeaf
class_name ActWaitTransition

## 变身等待：变身动画中保持 RUNNING，变身结束返回 FAILURE 让 CondPhaseTransitioning 失败退出

func tick(actor: Node, _bb: Blackboard) -> int:
	var boss: BossGhostWitch = actor as BossGhostWitch
	if boss == null:
		return FAILURE
	if boss._phase_transitioning:
		return RUNNING
	return FAILURE
