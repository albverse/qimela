extends ConditionLeaf

func tick(actor: Node, blackboard: Blackboard) -> int:
	var actor_id := str(actor.get_instance_id())
	var now_ms := float(Time.get_ticks_msec())
	for key in ["cd_scythe", "cd_tombstone", "cd_wind", "cd_tug"]:
		var end_ms: float = blackboard.get_value(key, 0.0, actor_id)
		if now_ms >= end_ms:
			return FAILURE
	return SUCCESS
