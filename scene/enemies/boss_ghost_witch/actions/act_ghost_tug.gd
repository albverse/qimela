extends ActionLeaf
class_name ActGhostTug

enum Step { CAST, PULLING, SCYTHE }
var _step: int = Step.CAST
var _tug_instance: Node2D = null

func before_run(_actor: Node, _bb: Blackboard) -> void:
	_step = Step.CAST

func tick(actor: Node, blackboard: Blackboard) -> int:
	var boss := actor as BossGhostWitch
	if boss == null:
		return FAILURE
	match _step:
		Step.CAST:
			boss.anim_play(&"phase2/ghost_tug_cast", false)
			var player := boss.get_priority_attack_target()
			if player == null:
				return FAILURE
			_tug_instance = boss._ghost_tug_scene.instantiate()
			_tug_instance.add_to_group("ghost_tug")
			if _tug_instance.has_method("setup"):
				_tug_instance.call("setup", player, boss, boss.ghost_tug_pull_speed)
			player.add_child(_tug_instance)
			_step = Step.PULLING
		Step.PULLING:
			boss.anim_play(&"phase2/ghost_tug_loop", true)
			if _tug_instance == null or not is_instance_valid(_tug_instance):
				_set_cd(actor, blackboard, "cd_tug", boss.ghost_tug_cooldown)
				return SUCCESS
			for b in boss._scythe_detect_area.get_overlapping_bodies():
				if b.is_in_group("player"):
					_destroy_tug()
					_step = Step.SCYTHE
		Step.SCYTHE:
			boss.anim_play(&"phase2/scythe_slash", false)
			if boss.anim_is_finished(&"phase2/scythe_slash"):
				_set_cd(actor, blackboard, "cd_tug", boss.ghost_tug_cooldown)
				_set_cd(actor, blackboard, "cd_scythe", boss.scythe_slash_cooldown)
				return SUCCESS
	return RUNNING

func _destroy_tug() -> void:
	if _tug_instance and is_instance_valid(_tug_instance):
		_tug_instance.queue_free()
	_tug_instance = null

func _set_cd(actor: Node, bb: Blackboard, key: String, cd: float) -> void:
	bb.set_value(key, Time.get_ticks_msec() + cd * 1000.0, str(actor.get_instance_id()))

func interrupt(actor: Node, blackboard: Blackboard) -> void:
	_destroy_tug()
	_step = Step.CAST
	super(actor, blackboard)
