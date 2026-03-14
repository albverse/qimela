extends ActionLeaf
class_name ActScytheSlash

var _started: bool = false

func before_run(_actor: Node, _bb: Blackboard) -> void:
	_started = false

func tick(actor: Node, blackboard: Blackboard) -> int:
	var boss := actor as BossGhostWitch
	if boss == null:
		return FAILURE
	if not _started:
		_started = true
		boss.anim_play(&"phase2/scythe_slash", false)
	if boss.anim_is_finished(&"phase2/scythe_slash"):
		_set_cd(actor, blackboard, "cd_scythe", boss.scythe_slash_cooldown)
		return SUCCESS
	return RUNNING

func _set_cd(actor: Node, bb: Blackboard, key: String, cd: float) -> void:
	bb.set_value(key, Time.get_ticks_msec() + cd * 1000.0, str(actor.get_instance_id()))

func interrupt(actor: Node, blackboard: Blackboard) -> void:
	_started = false
	super(actor, blackboard)
