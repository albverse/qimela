extends ConditionLeaf
class_name CondSoulDevourerPlayerTooCloseAndIdle

## P5：idle / wander 空闲态（含 aggro），且未处于任何攻击链时，玩家贴脸才允许进入强制隐身。
## wander 期间播放 normal/run，也应触发隐身-飞天（_has_knife 已排除持刀 run）。

func tick(actor: Node, _blackboard: Blackboard) -> int:
	var sd: SoulDevourer = actor as SoulDevourer
	if sd == null:
		return FAILURE
	if not sd.can_trigger_forced_invisible():
		return FAILURE
	if sd.is_forced_invisible_anim_playing():
		return FAILURE
	var player: Node2D = sd.get_priority_attack_target()
	if player == null:
		return FAILURE
	if sd.global_position.distance_to(player.global_position) > sd.forced_invisible_trigger_dist:
		return FAILURE
	return SUCCESS
