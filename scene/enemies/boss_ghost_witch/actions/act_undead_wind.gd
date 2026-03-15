extends ActionLeaf
class_name ActUndeadWind

## 亡灵气流：7秒内逐渐生成10只幽灵 + 随机时间生成1只精英亡灵

enum Step { CAST_ENTER, SPAWNING, CAST_END }
var _step: int = Step.CAST_ENTER
var _spawn_timer: float = 0.0
var _spawn_count: int = 0
var _elite_spawned: bool = false
var _elite_spawn_time: float = 0.0
var _type_cycle: int = 0
var _cast_end_started: bool = false

func before_run(actor: Node, _bb: Blackboard) -> void:
	_step = Step.CAST_ENTER
	_spawn_timer = 0.0
	_spawn_count = 0
	_elite_spawned = false
	_elite_spawn_time = randf_range(1.0, 6.0)
	_type_cycle = 0
	_cast_end_started = false

func tick(actor: Node, blackboard: Blackboard) -> int:
	var boss: BossGhostWitch = actor as BossGhostWitch
	if boss == null:
		return FAILURE
	var dt: float = get_physics_process_delta_time()

	match _step:
		Step.CAST_ENTER:
			boss.anim_play(&"phase2/undead_wind_cast", false)
			boss._set_realhurtbox_enabled(false)
			_step = Step.SPAWNING
			return RUNNING
		Step.SPAWNING:
			boss.anim_play(&"phase2/undead_wind_loop", true)
			_spawn_timer += dt
			var interval: float = lerpf(1.2, 0.3, clampf(_spawn_timer / boss.undead_wind_spawn_duration, 0.0, 1.0))
			if _spawn_count < boss.undead_wind_total_count:
				var expected_count: int = int(_spawn_timer / interval)
				if expected_count > _spawn_count:
					_spawn_wraith(boss)
					_spawn_count += 1
			if not _elite_spawned and _spawn_timer >= _elite_spawn_time:
				_spawn_elite(boss)
				_elite_spawned = true
			if _spawn_timer >= boss.undead_wind_spawn_duration:
				_step = Step.CAST_END
			return RUNNING
		Step.CAST_END:
			if not _cast_end_started:
				boss.anim_play(&"phase2/undead_wind_end", false)
				boss._set_realhurtbox_enabled(true)
				_cast_end_started = true
			if boss.anim_is_finished(&"phase2/undead_wind_end"):
				_set_cooldown(actor, blackboard, "cd_wind", boss.undead_wind_cooldown)
				return SUCCESS
			return RUNNING
	return FAILURE

func _spawn_wraith(boss: BossGhostWitch) -> void:
	var wraith: Node2D = (boss._ghost_wraith_scene as PackedScene).instantiate()
	wraith.add_to_group("ghost_wraith")
	var wraith_type: int = (_type_cycle % 3) + 1
	_type_cycle += 1
	if wraith.has_method("setup"):
		var player: Node2D = boss.get_priority_attack_target()
		wraith.call("setup", wraith_type, player, boss.global_position)
	wraith.global_position = boss.global_position
	boss.get_parent().add_child(wraith)

func _spawn_elite(boss: BossGhostWitch) -> void:
	var elite: Node2D = (boss._ghost_elite_scene as PackedScene).instantiate()
	elite.add_to_group("ghost_elite")
	if elite.has_method("setup"):
		var player: Node2D = boss.get_priority_attack_target()
		elite.call("setup", player, boss)
	elite.global_position = boss.global_position
	boss.get_parent().add_child(elite)

func _set_cooldown(actor: Node, bb: Blackboard, key: String, cd: float) -> void:
	bb.set_value(key, Time.get_ticks_msec() + cd * 1000.0, str(actor.get_instance_id()))

func interrupt(actor: Node, blackboard: Blackboard) -> void:
	_step = Step.CAST_ENTER
	_cast_end_started = false
	var boss: BossGhostWitch = actor as BossGhostWitch
	if boss:
		boss._set_realhurtbox_enabled(true)
	super(actor, blackboard)
