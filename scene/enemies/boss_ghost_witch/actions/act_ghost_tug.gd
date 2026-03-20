extends ActionLeaf
class_name ActGhostTug

## 幽灵拔河：召唤幽灵拉玩家到近身 → 镰刀斩

enum Step { CAST, PULLING, SCYTHE_SLASH }
var _step: int = Step.CAST
var _tug_instance: Node2D = null
var _slash_started: bool = false

func before_run(actor: Node, _bb: Blackboard) -> void:
	_step = Step.CAST
	_slash_started = false

func tick(actor: Node, blackboard: Blackboard) -> int:
	var boss: BossGhostWitch = actor as BossGhostWitch
	if boss == null:
		return FAILURE

	match _step:
		Step.CAST:
			boss.anim_play(&"phase2/ghost_tug_cast", false)
			var player: Node2D = boss.get_priority_attack_target()
			if player == null:
				return FAILURE
			_tug_instance = (boss._ghost_tug_scene as PackedScene).instantiate()
			_tug_instance.add_to_group("ghost_tug")
			if _tug_instance.has_method("setup"):
				_tug_instance.call("setup", player, boss, boss.ghost_tug_pull_speed)
			player.add_child(_tug_instance)
			_step = Step.PULLING
			return RUNNING
		Step.PULLING:
			boss.anim_play(&"phase2/ghost_tug_loop", true)
			if _tug_instance == null or not is_instance_valid(_tug_instance):
				_set_cooldown(actor, blackboard, "cd_tug", boss.ghost_tug_cooldown)
				return SUCCESS
			if _player_in_scythe_area(boss):
				_destroy_tug()
				_step = Step.SCYTHE_SLASH
			return RUNNING
		Step.SCYTHE_SLASH:
			if not _slash_started:
				boss.anim_play(&"phase2/scythe_slash", false)
				_slash_started = true
			if boss.anim_is_finished(&"phase2/scythe_slash"):
				_set_cooldown(actor, blackboard, "cd_tug", boss.ghost_tug_cooldown)
				_set_cooldown(actor, blackboard, "cd_scythe", boss.scythe_slash_cooldown)
				return SUCCESS
			return RUNNING
	return FAILURE

func _player_in_scythe_area(boss: BossGhostWitch) -> bool:
	for body: Node2D in boss._scythe_detect_area.get_overlapping_bodies():
		if body.is_in_group("player"):
			return true
	return false

func _destroy_tug() -> void:
	if _tug_instance != null and is_instance_valid(_tug_instance):
		_tug_instance.queue_free()
		_tug_instance = null

func _set_cooldown(actor: Node, bb: Blackboard, key: String, cd: float) -> void:
	bb.set_value(key, Time.get_ticks_msec() + cd * 1000.0, str(actor.get_instance_id()))

func interrupt(actor: Node, blackboard: Blackboard) -> void:
	_destroy_tug()
	_step = Step.CAST
	_slash_started = false
	super(actor, blackboard)
