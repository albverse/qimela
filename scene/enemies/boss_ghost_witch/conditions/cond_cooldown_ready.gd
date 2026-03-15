extends ConditionLeaf

@export var cooldown_key: String = "cd_skill"
@export var cooldown_sec: float = 1.0

func tick(actor: Node, blackboard: Blackboard) -> int:
	var actor_id := str(actor.get_instance_id())
	var end_ms: float = blackboard.get_value(cooldown_key, 0.0, actor_id)
	if Time.get_ticks_msec() < end_ms:
		return FAILURE
	return SUCCESS
