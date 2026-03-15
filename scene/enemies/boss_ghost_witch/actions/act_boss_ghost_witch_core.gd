extends ActionLeaf
class_name ActBossGhostWitchCore

func tick(actor: Node, _blackboard: Blackboard) -> int:
	var boss := actor as BossGhostWitch
	if boss == null:
		return FAILURE
	boss.ai_tick(actor.get_physics_process_delta_time())
	return RUNNING

func interrupt(actor: Node, blackboard: Blackboard) -> void:
	super(actor, blackboard)
