## 变身等待 Action：变身动画播放期间保持 RUNNING
extends ActionLeaf
class_name ActWaitTransition

func tick(actor: Node, _bb: Blackboard) -> int:
	var boss := actor as BossGhostWitch
	if boss == null:
		return FAILURE
	if boss._phase_transitioning:
		return RUNNING  # 变身动画还没播完，保持 RUNNING
	return FAILURE  # 变身结束，让 CondPhaseTransitioning 失败，退出此分支
