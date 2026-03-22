extends ConditionLeaf
class_name CondSoulDevourerPlayerTooCloseAndIdle

## P5：玩家距离 < forced_invisible_trigger_dist 且当前为 idle 状态（不在 aggro 中）。
## 触发强制隐身。

func tick(actor: Node, _blackboard: Blackboard) -> int:
	var sd: SoulDevourer = actor as SoulDevourer
	if sd == null:
		return FAILURE
	# 仅在显现非 aggro 状态下检查
	if sd._is_floating_invisible or sd._forced_invisible:
		return FAILURE
	if sd._aggro_mode:
		return FAILURE

	var player: Node2D = sd.get_priority_attack_target()
	if player == null:
		return FAILURE
	var dist: float = sd.global_position.distance_to(player.global_position)
	if dist < sd.forced_invisible_trigger_dist:
		return SUCCESS
	return FAILURE
