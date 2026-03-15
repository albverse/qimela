extends ActionLeaf
class_name ActWaitTransition

func tick(actor: Node, _blackboard: Blackboard) -> int:
	var boss := actor as BossGhostWitch
	if boss == null:
		return FAILURE
	if not boss._phase_transitioning:
		return SUCCESS
	if boss.anim_is_finished(&"phase1/phase1_to_phase2") or boss.anim_is_finished(&"phase2/phase2_to_phase3"):
		boss.finish_phase_transition()
		return SUCCESS
	boss.velocity.x = 0.0
	return RUNNING
