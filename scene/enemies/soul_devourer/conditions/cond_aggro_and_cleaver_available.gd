extends ConditionLeaf
class_name CondSoulDevourerAggroAndCleaverAvailable

## P6：aggro 模式下有斩魂刀可拾取，且技能 CD 已就绪。
## 冷却时间戳存在 blackboard（自管理，不受 interrupt 重置）。

const COOLDOWN_KEY: StringName = &"sd_cleaver_pickup_cd_end"

func tick(actor: Node, blackboard: Blackboard) -> int:
	var sd: SoulDevourer = actor as SoulDevourer
	if sd == null:
		return FAILURE
	if not sd._aggro_mode:
		return FAILURE
	if sd._has_knife:
		return FAILURE
	# 隐身/漂浮状态不拾取刀（仅显现状态才拾取）
	if sd._is_floating_invisible or sd._forced_invisible:
		return FAILURE

	# 已有正在拾取中的目标刀 → 跳过重新搜索（防止 SequenceReactive 重评导致无限中断）
	if sd._current_target_cleaver != null and is_instance_valid(sd._current_target_cleaver):
		return SUCCESS

	# 检查 CD
	var actor_id: String = str(actor.get_instance_id())
	var cd_end: float = blackboard.get_value(COOLDOWN_KEY, 0.0, actor_id)
	if SoulDevourer.now_sec() < cd_end:
		return FAILURE

	# 检查场上是否有可拾取的刀
	var cleaver: SoulCleaver = sd._find_nearest_cleaver()
	if cleaver == null:
		return FAILURE

	if Engine.get_physics_frames() % 60 == 0:
		print("[SD:P6cond] SUCCESS: aggro=%s knife=%s cleaver=%s dist=%.1f" % [
			sd._aggro_mode, sd._has_knife, cleaver.name,
			sd.global_position.distance_to(cleaver.global_position)])
	return SUCCESS
