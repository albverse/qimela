extends ConditionLeaf
class_name CondAllSkillsOnCooldown
func tick(actor: Node, blackboard: Blackboard) -> int:
	var actor_id := str(actor.get_instance_id())
	var now_ms := Time.get_ticks_msec()
	for key in ["cd_scythe", "cd_tombstone", "cd_wind", "cd_tug"]:
		if now_ms >= float(blackboard.get_value(key, 0.0, actor_id)):
			return FAILURE
	return SUCCESS
