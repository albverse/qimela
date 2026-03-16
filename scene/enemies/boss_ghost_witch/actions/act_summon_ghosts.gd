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
	var positions: Array[Vector2] = []
	positions.append(player.global_position)
	for i in range(boss.p3_summon_circle_count - 1):
		var random_x := player.global_position.x + randf_range(-300, 300)
		positions.append(Vector2(random_x, player.global_position.y))
	for pos in positions:
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
