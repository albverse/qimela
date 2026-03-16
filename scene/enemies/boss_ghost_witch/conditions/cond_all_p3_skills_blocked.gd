## Phase 3 用：检查所有主动技能是否都在冷却中或被阻止
extends ConditionLeaf
class_name CondAllP3SkillsOnCooldownOrBlocked

func tick(actor: Node, blackboard: Blackboard) -> int:
	var actor_id := str(actor.get_instance_id())
	var now_ms: float = Time.get_ticks_msec()
	var keys := ["cd_imprison", "cd_summon", "cd_dash", "cd_combo", "cd_kick"]
	for key in keys:
		var end_time: float = blackboard.get_value(key, 0.0, actor_id)
		if now_ms >= end_time:
			return FAILURE
	return SUCCESS
