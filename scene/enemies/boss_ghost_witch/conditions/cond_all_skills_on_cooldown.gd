## Phase 2 用：检查所有已使用过的主动技能是否都在冷却中
## 从未使用的技能（end_time=0）不计入判断，避免永远阻塞炸弹生成
extends ConditionLeaf
class_name CondAllSkillsOnCooldown

var _last_log_time: float = 0.0

func tick(actor: Node, blackboard: Blackboard) -> int:
	var actor_id := str(actor.get_instance_id())
	var now_ms: float = Time.get_ticks_msec()
	var available_skills: Array[String] = []
	var checked_count: int = 0
	for key in ["cd_scythe", "cd_tombstone", "cd_wind", "cd_tug"]:
		var end_time: float = blackboard.get_value(key, 0.0, actor_id)
		# 从未使用过的技能（end_time=0）跳过，不阻塞炸弹
		if end_time <= 0.0:
			continue
		checked_count += 1
		if now_ms >= end_time:
			available_skills.append(key)
	if checked_count == 0:
		# 没有任何技能被使用过 → 不应生成炸弹填充，Boss 应优先使用技能
		if now_ms - _last_log_time > 5000.0:
			_last_log_time = now_ms
			print("[COND_ALL_CD_DEBUG] FAILURE: no skills used yet (checked=0), skip bomb spawn")
		return FAILURE
	if available_skills.size() > 0:
		# 每 5 秒输出一次诊断日志
		if now_ms - _last_log_time > 5000.0:
			_last_log_time = now_ms
			var cd_info: String = ""
			for key in ["cd_scythe", "cd_tombstone", "cd_wind", "cd_tug"]:
				var end_time: float = blackboard.get_value(key, 0.0, actor_id)
				var remaining: float = (end_time - now_ms) / 1000.0
				cd_info += " %s=%.1fs" % [key, remaining]
			print("[COND_ALL_CD_DEBUG] FAILURE: available=%s (checked=%d) |%s" % [available_skills, checked_count, cd_info])
		return FAILURE  # 有已用过且已冷却完毕的技能
	# 所有已用过的技能都在CD中 → 允许生成炸弹填充
	if now_ms - _last_log_time > 5000.0:
		_last_log_time = now_ms
		print("[COND_ALL_CD_DEBUG] SUCCESS: checked=%d skills on cd, bombs can spawn" % checked_count)
	return SUCCESS
