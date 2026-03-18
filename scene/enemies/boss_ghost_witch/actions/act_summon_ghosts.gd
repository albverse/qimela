## 施法起手（含 combo3 攻击判定）→ 生成幽灵波次 → summon_loop 维持 → 等所有 GhostSummon 销毁 → 结束
## 全程不可移动
extends ActionLeaf
class_name ActSummonGhosts

enum Step { CAST, SUMMON_LOOP, DONE }
var _step: int = Step.CAST
var _wave_index: int = 0
var _wave_timer: float = 0.0
var _wave_interval: float = 0.0
var _cast_done: bool = false

func before_run(actor: Node, _bb: Blackboard) -> void:
	_step = Step.CAST
	_wave_index = 0
	_wave_timer = 0.0
	_cast_done = false

func tick(actor: Node, blackboard: Blackboard) -> int:
	var boss := actor as BossGhostWitch
	if boss == null:
		return FAILURE
	var dt := get_physics_process_delta_time()
	actor.velocity.x = 0.0  # 全程锁定移动

	match _step:
		Step.CAST:
			if not _cast_done:
				boss.anim_play(&"phase3/summon", false)
				_wave_interval = 5.0 / float(boss.p3_summon_wave_count)

			_wave_timer += dt
			var expected_waves := int(_wave_timer / _wave_interval)
			if expected_waves > _wave_index and _wave_index < boss.p3_summon_wave_count:
				_spawn_wave(boss)
				_wave_index += 1

			if boss.anim_is_finished(&"phase3/summon"):
				_cast_done = true
				_step = Step.SUMMON_LOOP
			return RUNNING

		Step.SUMMON_LOOP:
			boss.anim_play(&"phase3/summon_loop", true)
			if _wave_index < boss.p3_summon_wave_count:
				_wave_timer += dt
				var expected_waves := int(_wave_timer / _wave_interval)
				if expected_waves > _wave_index:
					_spawn_wave(boss)
					_wave_index += 1

			var remaining: Array[Node] = actor.get_tree().get_nodes_in_group("ghost_summon")
			if remaining.is_empty() and _wave_index >= boss.p3_summon_wave_count:
				boss.anim_play(&"phase3/idle", true)
				_set_cooldown(actor, blackboard, "cd_summon", boss.p3_summon_cooldown)
				return SUCCESS
			return RUNNING
	return FAILURE

func _spawn_wave(boss: BossGhostWitch) -> void:
	var player := boss.get_priority_attack_target()
	if player == null:
		return
	# 确定地面 Y 坐标：从玩家 X 轴线向下做射线找地面
	var ground_y: float = boss.global_position.y  # 默认用 Boss 所在 Y（Boss 在地面）
	var space := boss.get_world_2d().direct_space_state
	var ray_from := Vector2(player.global_position.x, player.global_position.y - 100.0)
	var ray_to := Vector2(player.global_position.x, player.global_position.y + 600.0)
	var q := PhysicsRayQueryParameters2D.create(ray_from, ray_to)
	q.collide_with_bodies = true
	q.collide_with_areas = false
	q.collision_mask = 1  # World(1)
	var hit := space.intersect_ray(q)
	if not hit.is_empty():
		ground_y = (hit.get("position", Vector2.ZERO) as Vector2).y

	# 生成位置：玩家 X 轴线下方的地面 + 随机偏移，保证间距 ≥ 60px
	var used_positions: Array[Vector2] = []
	var base_x: float = player.global_position.x
	# 第一个在玩家正下方地面
	used_positions.append(Vector2(base_x, ground_y))
	# 其余随机生成，保证不重叠（≥ 60px 间距）
	for i in range(boss.p3_summon_circle_count - 1):
		var spawn_x: float = base_x
		var attempts: int = 0
		var valid: bool = false
		while attempts < 20:
			spawn_x = base_x + randf_range(-300.0, 300.0)
			valid = true
			for existing in used_positions:
				if absf(spawn_x - existing.x) < 60.0:
					valid = false
					break
			if valid:
				break
			attempts += 1
		# 对该 X 做射线找地面 Y
		var pos_ground_y: float = ground_y
		var ray_from2 := Vector2(spawn_x, player.global_position.y - 100.0)
		var ray_to2 := Vector2(spawn_x, player.global_position.y + 600.0)
		var q2 := PhysicsRayQueryParameters2D.create(ray_from2, ray_to2)
		q2.collide_with_bodies = true
		q2.collide_with_areas = false
		q2.collision_mask = 1  # World(1)
		var hit2 := space.intersect_ray(q2)
		if not hit2.is_empty():
			pos_ground_y = (hit2.get("position", Vector2.ZERO) as Vector2).y
		used_positions.append(Vector2(spawn_x, pos_ground_y))

	for pos in used_positions:
		var summon: Node2D = boss._ghost_summon_scene.instantiate()
		summon.add_to_group("ghost_summon")
		if summon.has_method("setup"):
			summon.call("setup", 0.3)
		summon.global_position = pos
		boss.get_parent().add_child(summon)

func _set_cooldown(actor: Node, bb: Blackboard, key: String, cd: float) -> void:
	bb.set_value(key, Time.get_ticks_msec() + cd * 1000.0, str(actor.get_instance_id()))

func interrupt(actor: Node, blackboard: Blackboard) -> void:
	_step = Step.CAST
	_cast_done = false
	var boss := actor as BossGhostWitch
	if boss:
		boss._close_all_combo_hitboxes()
	super(actor, blackboard)
