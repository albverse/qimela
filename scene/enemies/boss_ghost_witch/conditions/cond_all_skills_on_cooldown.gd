## Phase 2 用：检查所有主动技能是否都在冷却中
extends ConditionLeaf
class_name CondAllSkillsOnCooldown

var _last_log_time: float = 0.0

func tick(actor: Node, blackboard: Blackboard) -> int:
	var actor_id := str(actor.get_instance_id())
	var now_ms: float = Time.get_ticks_msec()
	var available_skills: Array[String] = []
	# 只要任意一个技能可用，就返回 FAILURE（不是"全部冷却中"）
	for key in ["cd_scythe", "cd_tombstone", "cd_wind", "cd_tug"]:
		var end_time: float = blackboard.get_value(key, 0.0, actor_id)
		if now_ms >= end_time:
			available_skills.append(key)
	if available_skills.size() > 0:
		# 每 5 秒输出一次诊断日志
		if now_ms - _last_log_time > 5000.0:
			_last_log_time = now_ms
			var cd_info: String = ""
			for key in ["cd_scythe", "cd_tombstone", "cd_wind", "cd_tug"]:
				var end_time: float = blackboard.get_value(key, 0.0, actor_id)
				var remaining: float = (end_time - now_ms) / 1000.0
				cd_info += " %s=%.1fs" % [key, remaining]
			print("[COND_ALL_CD_DEBUG] FAILURE: available=%s |%s" % [available_skills, cd_info])
		return FAILURE  # 有技能可用
	print("[COND_ALL_CD_DEBUG] SUCCESS: all skills on cooldown, bombs can spawn")
	return SUCCESS  # 全部冷却中
