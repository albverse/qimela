extends ActionLeaf
class_name ActWaitTransition

func tick(actor: Node, _bb: Blackboard) -> int:
	var boss := actor as BossGhostWitch
	if boss == null:
		return FAILURE
	return RUNNING if boss._phase_transitioning else FAILURE
