extends ConditionLeaf
class_name CondSoulDevourerPlayerTooCloseAndIdle

## P5：idle / wander 空闲态（含 aggro），且未处于任何攻击链时，玩家贴脸才允许进入强制隐身。
## wander 期间播放 normal/run，也应触发隐身-飞天（_has_knife 已排除持刀 run）。

func tick(actor: Node, _blackboard: Blackboard) -> int:
	var sd: SoulDevourer = actor as SoulDevourer
	if sd == null:
		return FAILURE
	# 根因修复：一旦已经进入 forced_invisible 起手动画，
	# Reactive Sequence 必须持续看到 SUCCESS，直到动作叶自己完成。
	# 否则条件会因 _forced_invisible=true 在下一帧自我失效，
	# Action 被中断后就会留下 forced=true / float=false 的半状态卡死。
	if sd.is_forced_invisible_anim_playing():
		return SUCCESS
	if not sd.can_trigger_forced_invisible():
		return FAILURE
	var player: Node2D = sd.get_priority_attack_target()
	if player == null:
		return FAILURE
	if sd.global_position.distance_to(player.global_position) > sd.forced_invisible_trigger_dist:
		return FAILURE
	return SUCCESS
