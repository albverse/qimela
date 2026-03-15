extends ConditionLeaf

@export var value: int = 0

func tick(actor: Node, blackboard: Blackboard) -> int:
	var boss := actor as BossGhostWitch
	if boss == null:
		return FAILURE
	if blackboard != null:
		blackboard.set_value("player", boss.get_priority_attack_target())
	return SUCCESS
