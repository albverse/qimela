## Phase 3 用：检查所有主动技能是否都在冷却中或被阻止
## 当 SelectorReactive 走到 throw_scythe 时，说明所有高优先级分支的条件都未满足
## end_time == 0.0 表示技能从未使用过 → 视为"被条件阻止"（如果可用，更高优先级分支早已选中）
## end_time > 0.0 且 now_ms < end_time → 冷却中 → 视为阻止
## end_time > 0.0 且 now_ms >= end_time → 冷却已过期，技能可用 → FAILURE
extends ConditionLeaf
class_name CondAllP3SkillsOnCooldownOrBlocked

func tick(actor: Node, blackboard: Blackboard) -> int:
	var actor_id := str(actor.get_instance_id())
	var now_ms: float = Time.get_ticks_msec()
	var keys := ["cd_imprison", "cd_summon", "cd_dash", "cd_combo", "cd_kick"]
	for key in keys:
		var end_time: float = blackboard.get_value(key, 0.0, actor_id)
		# 从未使用（0.0）→ 视为被条件阻止，不算"可用"
		if is_zero_approx(end_time):
			continue
		# 冷却中 → 已阻止
		if now_ms < end_time:
			continue
		# 冷却过期且曾使用过 → 该技能可用，throw_scythe 不应触发
		return FAILURE
	return SUCCESS
