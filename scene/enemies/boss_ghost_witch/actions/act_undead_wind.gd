## 7秒内逐渐生成10只幽灵 + 随机时间生成1只精英亡灵
## 普通亡灵在Boss身后随机位置生成，直线往前飞
## 精英亡灵每次单次技能发动期间只能召唤一个
## 精英亡灵被玩家打败 → boss.hp - 1（由 GhostElite._on_death 调用）
## 期间 realhurtbox 不可攻击
extends ActionLeaf
class_name ActUndeadWind

enum Step { CAST_ENTER, SPAWNING, CAST_END, DONE }
var _step: int = Step.CAST_ENTER
var _spawn_timer: float = 0.0
var _spawn_count: int = 0
var _elite_spawned: bool = false
var _elite_spawn_time: float = 0.0  # 随机决定精英生成时机
var _type_cycle: int = 0  # 0,1,2 循环 → type1,type2,type3
var _step_entered: bool = false
var _cast_end_wait_frames: int = 0
var _cast_end_wait_sec: float = 0.0
var _last_cast_end_anim: StringName = &""

func before_run(actor: Node, _bb: Blackboard) -> void:
	_step = Step.CAST_ENTER
	_spawn_timer = 0.0
	_spawn_count = 0
	_elite_spawned = false
	_elite_spawn_time = randf_range(1.0, 6.0)
	_type_cycle = 0
	_step_entered = false
	_cast_end_wait_frames = 0
	_cast_end_wait_sec = 0.0
	_last_cast_end_anim = &""

func tick(actor: Node, blackboard: Blackboard) -> int:
	var boss := actor as BossGhostWitch
	if boss == null:
		return FAILURE
	actor.velocity.x = 0.0
	var dt := get_physics_process_delta_time()

	if not _step_entered:
		_step_entered = true
		print("[ACT_UNDEAD_WIND_DEBUG] enter_step=%d anim=%s hp=%d" % [_step, boss._current_anim, boss.hp])

	match _step:
		Step.CAST_ENTER:
			boss.anim_play(&"phase2/undead_wind_cast", false)
			boss._set_realhurtbox_enabled(false)  # 期间不可攻击
			_step = Step.SPAWNING
			_step_entered = false
			print("[ACT_UNDEAD_WIND_DEBUG] cast_enter, elite_spawn_time=%.1f" % _elite_spawn_time)
			return RUNNING
		Step.SPAWNING:
			boss.anim_play(&"phase2/undead_wind_loop", true)
			_spawn_timer += dt
			# 加速度生成：间隔随时间缩短
			var interval := lerpf(1.2, 0.3, clampf(_spawn_timer / boss.undead_wind_spawn_duration, 0.0, 1.0))
			# 简化：用计数和时间判断是否该生成下一只
			if _spawn_count < boss.undead_wind_total_count:
				var expected_count := int(_spawn_timer / interval)
				if expected_count > _spawn_count:
					_spawn_wraith(boss)
					_spawn_count += 1

			# 精英亡灵（每次技能发动只召唤一个）
			if not _elite_spawned and _spawn_timer >= _elite_spawn_time:
				_spawn_elite(boss)
				_elite_spawned = true

			if _spawn_timer >= boss.undead_wind_spawn_duration:
				_step = Step.CAST_END
				_step_entered = false
			return RUNNING
		Step.CAST_END:
			boss.anim_play(&"phase2/undead_wind_end", false)
			boss._set_realhurtbox_enabled(true)  # 恢复可攻击
			_cast_end_wait_frames += 1
			_cast_end_wait_sec += dt
			if boss._current_anim != _last_cast_end_anim:
				print("[ACT_UNDEAD_WIND_DEBUG] CAST_END anim_changed from=%s to=%s finished=%s loop=%s" % [_last_cast_end_anim, boss._current_anim, boss._current_anim_finished, boss._current_anim_loop])
				_last_cast_end_anim = boss._current_anim
			if _cast_end_wait_frames % 30 == 0:
				print("[ACT_UNDEAD_WIND_DEBUG] CAST_END waiting frames=%d sec=%.2f current_anim=%s finished_flag=%s anim_is_finished_end=%s loop=%s" % [_cast_end_wait_frames, _cast_end_wait_sec, boss._current_anim, boss._current_anim_finished, boss.anim_is_finished(&"phase2/undead_wind_end"), boss._current_anim_loop])
			if boss.anim_is_finished(&"phase2/undead_wind_end"):
				_set_cooldown(actor, blackboard, "cd_wind", boss.undead_wind_cooldown)
				print("[ACT_UNDEAD_WIND_DEBUG] cast_end success, spawned %d wraiths, elite=%s" % [_spawn_count, _elite_spawned])
				return SUCCESS
			return RUNNING
	return FAILURE

func _spawn_wraith(boss: BossGhostWitch) -> void:
	var wraith: Node2D = boss._ghost_wraith_scene.instantiate()
	wraith.add_to_group("ghost_wraith")
	# 设置 type (1,2,3 循环)
	var wraith_type := (_type_cycle % 3) + 1
	_type_cycle += 1
	var player := boss.get_priority_attack_target()
	if wraith.has_method("setup"):
		wraith.call("setup", wraith_type, player, boss.global_position)
	# 在 Boss 身后随机位置生成（远离玩家方向）
	var behind_dir: float = -1.0
	if player != null:
		behind_dir = -signf(player.global_position.x - boss.global_position.x)
		if behind_dir == 0.0:
			behind_dir = -1.0
	var random_offset_x: float = behind_dir * randf_range(20.0, 80.0)
	var random_offset_y: float = randf_range(-30.0, 30.0)
	wraith.global_position = Vector2(
		boss.global_position.x + random_offset_x,
		boss.global_position.y + random_offset_y
	)
	boss.get_parent().add_child(wraith)

func _spawn_elite(boss: BossGhostWitch) -> void:
	var elite: Node2D = boss._ghost_elite_scene.instantiate()
	elite.add_to_group("ghost_elite")
	if elite.has_method("setup"):
		var player := boss.get_priority_attack_target()
		elite.call("setup", player, boss)  # 传入 boss 引用，被击杀时扣 boss HP
	# 精英亡灵在 Boss 身后生成
	var player := boss.get_priority_attack_target()
	var behind_dir: float = -1.0
	if player != null:
		behind_dir = -signf(player.global_position.x - boss.global_position.x)
		if behind_dir == 0.0:
			behind_dir = -1.0
	elite.global_position = Vector2(
		boss.global_position.x + behind_dir * 50.0,
		boss.global_position.y
	)
	boss.get_parent().add_child(elite)
	print("[ACT_UNDEAD_WIND_DEBUG] elite spawned at %s" % elite.global_position)

func _set_cooldown(actor: Node, bb: Blackboard, key: String, cd: float) -> void:
	bb.set_value(key, Time.get_ticks_msec() + cd * 1000.0, str(actor.get_instance_id()))

func interrupt(actor: Node, blackboard: Blackboard) -> void:
	print("[ACT_UNDEAD_WIND_DEBUG] interrupt at step=%d cast_end_wait_frames=%d cast_end_wait_sec=%.2f current_anim=%s finished=%s" % [_step, _cast_end_wait_frames, _cast_end_wait_sec, (actor as BossGhostWitch)._current_anim if actor is BossGhostWitch else &"", (actor as BossGhostWitch)._current_anim_finished if actor is BossGhostWitch else false])
	_step = Step.CAST_ENTER
	_step_entered = false
	_cast_end_wait_frames = 0
	_cast_end_wait_sec = 0.0
	_last_cast_end_anim = &""
	if actor != null:
		actor.velocity.x = 0.0
	var boss := actor as BossGhostWitch
	if boss:
		boss._set_realhurtbox_enabled(true)
	super(actor, blackboard)
