extends ActionLeaf
class_name ActRepairRestArea

## Act_RepairRestArea（飞行前往并修复 rest_area_break）
## 触发条件：mode == REPAIRING（由 ActChasePlayer 在玩家超出追击范围且无 rest_area 时切换）
##
## 内部阶段（按执行顺序）：
##   FLYING_TO_BREAK  → fly_move 飞向最近的 rest_area_break
##   REPAIRING_LOOP   → fix_rest_area_loop（loop）；每 1s 为目标 hp+1
##   FLYING_AWAY      → 修复完成后，fly_move 飞离 rest_area 50px（向上偏移）
##   HOVERING_WAIT    → fly_idle 悬停 2s，然后切 RETURN_TO_REST 回巢
##
## 玩家检测中断（任一阶段均检测）：
##   - 检测到玩家进入 chase_range_px → 放弃修复，切 FLYING_ATTACK
##   - 受击/眩晕由 BT SelectorReactive 高优先级序列自动抢占，interrupt() 清理本地状态
##
## 约束：若 FLYING_AWAY / HOVERING_WAIT 期间修复好的 rest_area 再次被打坏
##       → 鸟已在附近，直接重新进入 REPAIRING_LOOP 修复

enum Phase { FLYING_TO_BREAK, REPAIRING_LOOP, FLYING_AWAY, HOVERING_WAIT }

const REACH_THRESHOLD_PX: float = 30.0
const HOVER_AWAY_DIST: float = 50.0      ## 修复完成后飞离 rest_area 的距离（px）
const HOVER_AWAY_REACH_PX: float = 10.0  ## 到达悬停点的判定阈值（px）
const POST_REPAIR_HOVER_SEC: float = 2.0 ## 修复完成后悬停等待时间（s）

var _phase: int = Phase.FLYING_TO_BREAK
var _repair_elapsed: float = 0.0
var _hover_elapsed: float = 0.0
var _repaired_area: Node2D = null  ## 刚修复完的区域引用（FLYING_AWAY / HOVERING_WAIT 阶段用）
var _hover_target: Vector2 = Vector2.ZERO  ## 修复完成后的悬停目标坐标


func before_run(actor: Node, _blackboard: Blackboard) -> void:
	var bird := actor as StoneMaskBird
	if bird == null:
		return

	_phase = Phase.FLYING_TO_BREAK
	_repair_elapsed = 0.0
	_hover_elapsed = 0.0
	_repaired_area = null

	var break_area := _find_nearest_break(bird)
	if break_area == null:
		# 没有目标：立刻退回飞行攻击，避免卡死
		_do_abort(bird)
		return

	bird.target_repair_area = break_area
	bird.anim_play(&"fly_move", true, true)


func tick(actor: Node, _blackboard: Blackboard) -> int:
	var bird := actor as StoneMaskBird
	if bird == null:
		return FAILURE

	# 外部强制改了 mode（apply_hit 设为 HURT/STUNNED）→ BT 高优先级接管
	if bird.mode != StoneMaskBird.Mode.REPAIRING:
		return SUCCESS

	var dt := actor.get_physics_process_delta_time()

	match _phase:
		Phase.FLYING_TO_BREAK:
			return _tick_flying_to_break(bird, dt)
		Phase.REPAIRING_LOOP:
			return _tick_repairing_loop(bird, dt)
		Phase.FLYING_AWAY:
			return _tick_flying_away(bird, dt)
		Phase.HOVERING_WAIT:
			return _tick_hovering_wait(bird, dt)

	return RUNNING


# ──────────────────────────────────────────────────────────
# 阶段一：飞向 rest_area_break
# ──────────────────────────────────────────────────────────

func _tick_flying_to_break(bird: StoneMaskBird, _dt: float) -> int:
	if bird.target_repair_area == null or not is_instance_valid(bird.target_repair_area):
		return _do_abort(bird)

	if _player_in_chase_range(bird):
		return _do_abort(bird)

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
		return _do_abort(bird)

	if _player_in_chase_range(bird):
		bird.target_repair_area = null
		return _do_abort(bird)

	if not bird.anim_is_playing(&"fix_rest_area_loop"):
		bird.anim_play(&"fix_rest_area_loop", true, true)

	_repair_elapsed += dt
	while _repair_elapsed >= 1.0:
		_repair_elapsed -= 1.0
		var fully_repaired := false
		if bird.target_repair_area.has_method("add_repair_progress"):
			fully_repaired = bool(bird.target_repair_area.call("add_repair_progress"))
		if fully_repaired:
			# 修复完成 → 保存引用、进入飞离阶段
			_repaired_area = bird.target_repair_area
			bird.target_repair_area = null
			_hover_target = _repaired_area.global_position + Vector2(0.0, -HOVER_AWAY_DIST)
			_enter_flying_away(bird)
			return RUNNING

	return RUNNING


# ──────────────────────────────────────────────────────────
# 阶段三：修复完成后飞离 50px（正上方）
# ──────────────────────────────────────────────────────────

func _tick_flying_away(bird: StoneMaskBird, _dt: float) -> int:
	if _repaired_area == null or not is_instance_valid(_repaired_area):
		return _do_abort(bird)

	# 修复好的区域再次被打坏 → 就地重新修复（已在附近）
	if _repaired_area.is_in_group("rest_area_break"):
		bird.target_repair_area = _repaired_area
		_repaired_area = null
		_enter_repairing_loop(bird)
		return RUNNING

	var to_hover := _hover_target - bird.global_position
	var dist := to_hover.length()

	if dist > HOVER_AWAY_REACH_PX:
		bird.velocity = to_hover.normalized() * bird.return_speed
		bird.move_and_slide()
		if not bird.anim_is_playing(&"fly_move"):
			bird.anim_play(&"fly_move", true, true)
		return RUNNING

	# 到达悬停点
	bird.velocity = Vector2.ZERO
	_enter_hovering_wait(bird)
	return RUNNING


# ──────────────────────────────────────────────────────────
# 阶段四：悬停 2s 后飞回 rest_area
# ──────────────────────────────────────────────────────────

func _tick_hovering_wait(bird: StoneMaskBird, dt: float) -> int:
	if _repaired_area == null or not is_instance_valid(_repaired_area):
		return _do_abort(bird)

	# 修复好的区域再次被打坏 → 返回 FLYING_TO_BREAK 就近修复
	if _repaired_area.is_in_group("rest_area_break"):
		bird.target_repair_area = _repaired_area
		_repaired_area = null
		_phase = Phase.FLYING_TO_BREAK
		_repair_elapsed = 0.0
		bird.anim_play(&"fly_move", true, true)
		return RUNNING

	if not bird.anim_is_playing(&"fly_idle"):
		bird.anim_play(&"fly_idle", true, true)

	_hover_elapsed += dt
	if _hover_elapsed < POST_REPAIR_HOVER_SEC:
		return RUNNING

	# 2s 到 → 切 RETURN_TO_REST（ActReturnToRest 会自动选可用巢穴）
	_repaired_area = null
	bird.mode = StoneMaskBird.Mode.RETURN_TO_REST
	return SUCCESS


# ──────────────────────────────────────────────────────────
# 内部工具方法
# ──────────────────────────────────────────────────────────

func _enter_repairing_loop(bird: StoneMaskBird) -> void:
	_phase = Phase.REPAIRING_LOOP
	_repair_elapsed = 0.0
	bird.anim_play(&"fix_rest_area_loop", true, true)


func _enter_flying_away(bird: StoneMaskBird) -> void:
	_phase = Phase.FLYING_AWAY
	bird.anim_play(&"fly_move", true, true)


func _enter_hovering_wait(bird: StoneMaskBird) -> void:
	_phase = Phase.HOVERING_WAIT
	_hover_elapsed = 0.0
	bird.anim_play(&"fly_idle", true, true)


func _do_abort(bird: StoneMaskBird) -> int:
	bird.target_repair_area = null
	_repaired_area = null
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
		# target_repair_area 保留：下次重入 REPAIRING 时继续找同一目标
	_phase = Phase.FLYING_TO_BREAK
	_repair_elapsed = 0.0
	_hover_elapsed = 0.0
	_repaired_area = null
	super(actor, blackboard)
