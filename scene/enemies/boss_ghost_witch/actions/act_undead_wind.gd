extends ActionLeaf
class_name ActUndeadWind

enum Step { CAST_ENTER, SPAWNING, CAST_END }
var _step: int = Step.CAST_ENTER
var _spawn_timer: float = 0.0
var _spawn_count: int = 0
var _elite_spawned: bool = false
var _elite_spawn_time: float = 3.0

func before_run(_actor: Node, _bb: Blackboard) -> void:
	_step = Step.CAST_ENTER
	_spawn_timer = 0.0
	_spawn_count = 0
	_elite_spawned = false
	_elite_spawn_time = randf_range(1.0, 6.0)

func tick(actor: Node, blackboard: Blackboard) -> int:
	var boss := actor as BossGhostWitch
	if boss == null:
		return FAILURE
	var dt := get_physics_process_delta_time()
	match _step:
		Step.CAST_ENTER:
			boss.anim_play(&"phase2/undead_wind_cast", false)
			boss._set_realhurtbox_enabled(false)
			_step = Step.SPAWNING
		Step.SPAWNING:
			boss.anim_play(&"phase2/undead_wind_loop", true)
			_spawn_timer += dt
			if _spawn_count < boss.undead_wind_total_count and int(_spawn_timer * 2.0) > _spawn_count:
				_spawn_wraith(boss)
				_spawn_count += 1
			if not _elite_spawned and _spawn_timer >= _elite_spawn_time:
				_spawn_elite(boss)
				_elite_spawned = true
			if _spawn_timer >= boss.undead_wind_spawn_duration:
				_step = Step.CAST_END
		Step.CAST_END:
			boss.anim_play(&"phase2/undead_wind_end", false)
			boss._set_realhurtbox_enabled(true)
			if boss.anim_is_finished(&"phase2/undead_wind_end"):
				_set_cd(actor, blackboard, "cd_wind", boss.undead_wind_cooldown)
				return SUCCESS
	return RUNNING

func _spawn_wraith(boss: BossGhostWitch) -> void:
	var w := boss._ghost_wraith_scene.instantiate()
	w.add_to_group("ghost_wraith")
	if w.has_method("setup"):
		w.call("setup", (_spawn_count % 3) + 1, boss.get_priority_attack_target(), boss.global_position)
	w.global_position = boss.global_position
	boss.get_parent().add_child(w)

func _spawn_elite(boss: BossGhostWitch) -> void:
	var e := boss._ghost_elite_scene.instantiate()
	e.add_to_group("ghost_elite")
	if e.has_method("setup"):
		e.call("setup", boss.get_priority_attack_target(), boss)
	e.global_position = boss.global_position
	boss.get_parent().add_child(e)

func _set_cd(actor: Node, bb: Blackboard, key: String, cd: float) -> void:
	bb.set_value(key, Time.get_ticks_msec() + cd * 1000.0, str(actor.get_instance_id()))

func interrupt(actor: Node, blackboard: Blackboard) -> void:
	var boss := actor as BossGhostWitch
	if boss:
		boss._set_realhurtbox_enabled(true)
	_step = Step.CAST_ENTER
	super(actor, blackboard)
