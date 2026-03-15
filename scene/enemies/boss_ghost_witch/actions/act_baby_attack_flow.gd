extends ActionLeaf

func tick(actor: Node, _blackboard: Blackboard) -> int:
	var boss := actor as BossGhostWitch
	if boss == null:
		return FAILURE
	return RUNNING

func interrupt(actor: Node, blackboard: Blackboard) -> void:
	super(actor, blackboard)
