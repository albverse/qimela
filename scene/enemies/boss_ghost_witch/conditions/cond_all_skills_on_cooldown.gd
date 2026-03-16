## Phase 2 用：检查所有主动技能是否都在冷却中
extends ConditionLeaf
class_name CondAllSkillsOnCooldown

func tick(actor: Node, blackboard: Blackboard) -> int:
	var actor_id := str(actor.get_instance_id())
	var now_ms: float = Time.get_ticks_msec()
	# 只要任意一个技能可用，就返回 FAILURE（不是"全部冷却中"）
	for key in ["cd_scythe", "cd_tombstone", "cd_wind", "cd_tug"]:
		var end_time: float = blackboard.get_value(key, 0.0, actor_id)
		if now_ms >= end_time:
			return FAILURE  # 有技能可用
	return SUCCESS  # 全部冷却中
