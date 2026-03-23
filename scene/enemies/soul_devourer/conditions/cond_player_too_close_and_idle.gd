extends ConditionLeaf
class_name CondSoulDevourerPlayerTooCloseAndIdle

## P5：闲逛期间玩家贴脸 → 强制隐身。

func tick(actor: Node, _blackboard: Blackboard) -> int:
	var sd: SoulDevourer = actor as SoulDevourer
	if sd == null:
		return FAILURE
	if not sd._is_wandering:
		return FAILURE
	if sd._is_floating_invisible or sd._forced_invisible or sd._landing_locked or sd._has_knife:
		return FAILURE
	var player: Node2D = sd.get_priority_attack_target()
	if player == null:
		return FAILURE
	if sd.global_position.distance_to(player.global_position) > sd.forced_invisible_trigger_dist:
		return FAILURE
	return SUCCESS
