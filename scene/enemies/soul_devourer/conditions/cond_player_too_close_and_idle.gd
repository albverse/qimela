extends ConditionLeaf
class_name CondSoulDevourerPlayerTooCloseAndIdle

## P5：idle 空闲态（含 aggro），且未处于任何攻击链时，玩家贴脸才允许进入强制隐身。
## aggro 模式下若无刀/CD中/无幽灵，SD 会落入 idle，此时也应允许隐身-飞天。

func tick(actor: Node, _blackboard: Blackboard) -> int:
	var sd: SoulDevourer = actor as SoulDevourer
	if sd == null:
		return FAILURE
	if sd._is_floating_invisible or sd._forced_invisible or sd._landing_locked or sd._has_knife:
		return FAILURE
	if sd._is_full:
		return FAILURE
	if not String(sd._current_anim).ends_with("/idle"):
		return FAILURE
	var player: Node2D = sd.get_priority_attack_target()
	if player == null:
		return FAILURE
	if sd.global_position.distance_to(player.global_position) > sd.forced_invisible_trigger_dist:
		return FAILURE
	return SUCCESS
