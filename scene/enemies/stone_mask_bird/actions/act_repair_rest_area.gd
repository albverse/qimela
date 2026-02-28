extends ActionLeaf
class_name ActRepairRestArea

## Act_RepairRestArea（飞行前往并修复 rest_area_break）
## 触发条件：mode == REPAIRING（由 ActChasePlayer 在玩家超出追击范围且无 rest_area 时切换）
##
## 内部阶段：
##   FLYING_TO_BREAK  → fly_move 飞向最近的 rest_area_break
##   REPAIRING_LOOP   → fix_rest_area_loop（loop）；每 1s 为目标 hp+1
##
## 中断条件（由 BT SelectorReactive 高优先级序列自动抢占）：
##   - 被 hurt/stun/weak 打断：mode 已被 apply_hit 改为 HURT/STUNNED，BT 自然切走
##   - 在任一阶段检测到玩家进入追击范围 → 内部切回 FLYING_ATTACK
##
## 修复完成：rest_area_break.add_repair_progress() 返回 true
##   → RestArea 恢复为 rest_area 组、全功能 → bird 切 FLYING_ATTACK

enum Phase { FLYING_TO_BREAK, REPAIRING_LOOP }

const REACH_THRESHOLD_PX: float = 30.0

var _phase: int = Phase.FLYING_TO_BREAK
var _repair_elapsed: float = 0.0
var _phase_enter_sec: float = 0.0


func before_run(actor: Node, _blackboard: Blackboard) -> void:
	var bird := actor as StoneMaskBird
	if bird == null:
		return

	_phase = Phase.FLYING_TO_BREAK
	_repair_elapsed = 0.0
	_phase_enter_sec = StoneMaskBird.now_sec()

	# 选择最近的 rest_area_break
	var break_area := _find_nearest_break(bird)
	if break_area == null:
		# 无目标：回到飞行攻击模式避免卡死
		bird.mode = StoneMaskBird.Mode.FLYING_ATTACK
		var now := StoneMaskBird.now_sec()
		bird.attack_until_sec = now + bird.attack_duration_sec
		bird.next_attack_sec = now
		return

	bird.target_repair_area = break_area
	bird.anim_play(&"fly_move", true, true)


func tick(actor: Node, _blackboard: Blackboard) -> int:
	var bird := actor as StoneMaskBird
	if bird == null:
		return FAILURE

	# 模式被外部改变（apply_hit 设置了 HURT/STUNNED）→ 让 BT 高优先级接管
	if bird.mode != StoneMaskBird.Mode.REPAIRING:
		return SUCCESS

	var dt := actor.get_physics_process_delta_time()

	match _phase:
		Phase.FLYING_TO_BREAK:
			return _tick_flying_to_break(bird, dt)
		Phase.REPAIRING_LOOP:
			return _tick_repairing_loop(bird, dt)

	return RUNNING


# ──────────────────────────────────────────────────────────
# 阶段一：飞向 rest_area_break
# ──────────────────────────────────────────────────────────

func _tick_flying_to_break(bird: StoneMaskBird, dt: float) -> int:
	if bird.target_repair_area == null or not is_instance_valid(bird.target_repair_area):
		return _abort_to_flying_attack(bird)

	# 优先检测玩家：进入追击范围立刻放弃修复
	if _player_in_chase_range(bird):
		return _abort_to_flying_attack(bird)

	var to_break := bird.target_repair_area.global_position - bird.global_position
	var dist := to_break.length()

	if dist > REACH_THRESHOLD_PX:
		bird.velocity = to_break.normalized() * bird.return_speed
		bird.move_and_slide()
		if not bird.anim_is_playing(&"fly_move"):
			bird.anim_play(&"fly_move", true, true)
		return RUNNING

	# 到达目标
	bird.velocity = Vector2.ZERO
	bird.global_position = bird.target_repair_area.global_position
	_enter_repairing_loop(bird)
	return RUNNING


# ──────────────────────────────────────────────────────────
# 阶段二：原地修复循环
# ──────────────────────────────────────────────────────────

func _tick_repairing_loop(bird: StoneMaskBird, dt: float) -> int:
	if bird.target_repair_area == null or not is_instance_valid(bird.target_repair_area):
		return _abort_to_flying_attack(bird)

	# 优先检测玩家：进入追击范围立刻放弃修复
	if _player_in_chase_range(bird):
		bird.target_repair_area = null
		return _abort_to_flying_attack(bird)

	# 确保动画持续播放（被外部短暂打断也能自动续播）
	if not bird.anim_is_playing(&"fix_rest_area_loop"):
		bird.anim_play(&"fix_rest_area_loop", true, true)

	# 每 1 秒为目标 hp+1
	_repair_elapsed += dt
	while _repair_elapsed >= 1.0:
		_repair_elapsed -= 1.0
		var fully_repaired := false
		if bird.target_repair_area.has_method("add_repair_progress"):
			fully_repaired = bool(bird.target_repair_area.call("add_repair_progress"))
		if fully_repaired:
			# rest_area_break 已修复完成，恢复为 rest_area
			bird.target_repair_area = null
			var now := StoneMaskBird.now_sec()
			bird.mode = StoneMaskBird.Mode.FLYING_ATTACK
			bird.attack_until_sec = now + bird.attack_duration_sec
			bird.next_attack_sec = now
			return SUCCESS

	return RUNNING


# ──────────────────────────────────────────────────────────
# 内部工具方法
# ──────────────────────────────────────────────────────────

func _enter_repairing_loop(bird: StoneMaskBird) -> void:
	_phase = Phase.REPAIRING_LOOP
	_repair_elapsed = 0.0
	_phase_enter_sec = StoneMaskBird.now_sec()
	bird.anim_play(&"fix_rest_area_loop", true, true)


func _abort_to_flying_attack(bird: StoneMaskBird) -> int:
	bird.target_repair_area = null
	var now := StoneMaskBird.now_sec()
	bird.mode = StoneMaskBird.Mode.FLYING_ATTACK
	bird.attack_until_sec = now + bird.attack_duration_sec
	bird.next_attack_sec = now
	return SUCCESS


func _player_in_chase_range(bird: StoneMaskBird) -> bool:
	var player := bird._get_player()
	if player == null:
		return false
	return bird.global_position.distance_to(player.global_position) <= bird.chase_range_px


func _find_nearest_break(bird: StoneMaskBird) -> Node2D:
	var break_areas := bird.get_tree().get_nodes_in_group("rest_area_break")
	if break_areas.is_empty():
		return null
	var nearest: Node2D = null
	var nearest_dist: float = INF
	for n in break_areas:
		var area := n as Node2D
		if area == null:
			continue
		var d := bird.global_position.distance_to(area.global_position)
		if d < nearest_dist:
			nearest_dist = d
			nearest = area
	return nearest


func interrupt(actor: Node, blackboard: Blackboard) -> void:
	var bird := actor as StoneMaskBird
	if bird:
		bird.velocity = Vector2.ZERO
		bird.anim_stop_or_blendout()
		# 保留 target_repair_area，使下次进入 REPAIRING 时可继续找原目标
	_phase = Phase.FLYING_TO_BREAK
	_repair_elapsed = 0.0
	super(actor, blackboard)
