extends ConditionLeaf
class_name CondSoulDevourerAggroAndFull

## P8：aggro 模式下处于 full 状态（已吞食幽灵），触发光炮。
## 包含 CD 检查（自管理）。

const COOLDOWN_KEY: StringName = &"sd_light_beam_cd_end"

func tick(actor: Node, blackboard: Blackboard) -> int:
	var sd: SoulDevourer = actor as SoulDevourer
	if sd == null:
		return FAILURE
	if not sd._aggro_mode:
		return FAILURE
	if not sd._is_full:
		return FAILURE

	# 检查距离（光炮需要最小距离）
	var player: Node2D = sd.get_priority_attack_target()
	if player != null:
		var dist: float = sd.global_position.distance_to(player.global_position)
		if dist < sd.light_beam_min_distance:
			return FAILURE

	# 检查 CD
	var actor_id: String = str(actor.get_instance_id())
	var cd_end: float = blackboard.get_value(COOLDOWN_KEY, 0.0, actor_id)
	if SoulDevourer.now_sec() < cd_end:
		return FAILURE

	return SUCCESS
