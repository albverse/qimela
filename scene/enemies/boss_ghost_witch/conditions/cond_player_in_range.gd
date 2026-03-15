extends ConditionLeaf
class_name CondPlayerInRange

@export var range_px: float = 500.0

func tick(actor: Node, blackboard: Blackboard) -> int:
	var boss := actor as BossGhostWitch
	if boss == null:
		return FAILURE
	var player := boss.get_priority_attack_target()
	if player == null:
		return FAILURE
	var h_dist := absf(player.global_position.x - boss.global_position.x)
	if h_dist <= range_px:
		blackboard.set_value("player", player, str(actor.get_instance_id()))
		return SUCCESS
	return FAILURE
