extends ActionLeaf
class_name ActReturnToRest

## Act_ReturnToRest（飞行 -> 回巢 -> 倒下）
## 从 RETURN_TO_REST 状态回到休息点。
## 与 ActWakeFlyReturnRest 类似但不需要苏醒/升空阶段（已在空中）。
## 内部阶段：FLYING_TO_REST -> SLEEPING_DOWN
## 完成后：mode=RESTING，HP=3。
## 无 rest_area 时：mode=FLYING_ATTACK（避免卡死）。

enum Phase { FLYING_TO_REST, SLEEPING_DOWN }

var _phase: int = Phase.FLYING_TO_REST

func before_run(actor: Node, _blackboard: Blackboard) -> void:
	var bird := actor as StoneMaskBird
	if bird == null:
		return
	_phase = Phase.FLYING_TO_REST

	bird._release_target_rest()
	var rest_area := _pick_available_rest_area(bird)
	if rest_area == null:
		var break_area := _pick_nearest_break_area(bird)
		if break_area != null:
			bird.target_repair_area = break_area
			bird.mode = StoneMaskBird.Mode.REPAIRING
			return
		# 无 rest_area / break_area -> 回到飞行攻击
		bird.mode = StoneMaskBird.Mode.FLYING_ATTACK
		var now := StoneMaskBird.now_sec()
		bird.attack_until_sec = now + bird.attack_duration_sec
		bird.next_attack_sec = now
		return
	bird.anim_play(&"fly_move", true, true)


func tick(actor: Node, _blackboard: Blackboard) -> int:
	var bird := actor as StoneMaskBird
	if bird == null:
		return FAILURE

	# before_run 中发现无 rest_area 已切换 mode，直接 SUCCESS 让 BT 切走
	if bird.mode != StoneMaskBird.Mode.RETURN_TO_REST:
		return SUCCESS

	var dt: float = actor.get_physics_process_delta_time()

	match _phase:
		Phase.FLYING_TO_REST:
			return _tick_flying_to_rest(bird, dt)
		Phase.SLEEPING_DOWN:
			return _tick_sleeping_down(bird)
	return RUNNING


func _tick_flying_to_rest(bird: StoneMaskBird, dt: float) -> int:
	if bird.target_rest == null or not is_instance_valid(bird.target_rest):
		# 目标丢失 -> 回到飞行攻击
		bird._release_target_rest()
		bird.mode = StoneMaskBird.Mode.FLYING_ATTACK
		return SUCCESS

	# rest_area 在飞行途中被摧毁（已转为 rest_area_break）→ 继续飞过去：
	# 规格约束：优先飞回原巢位置，到达后立刻切 REPAIRING 修复
	var is_now_break: bool = not bird.target_rest.is_in_group("rest_area")

	var to_rest := bird.target_rest.global_position - bird.global_position
	if not _has_arrived_to_rest(bird):
		bird.velocity = to_rest.normalized() * bird.return_speed
		bird.move_and_slide()
		return RUNNING

	# 到达目标位置
	bird.global_position = bird.target_rest.global_position
	bird.velocity = Vector2.ZERO

	if is_now_break:
		# 目标已变成 rest_area_break → 就地切换 REPAIRING 修复
		bird.target_repair_area = bird.target_rest
		bird._release_target_rest()
		bird.mode = StoneMaskBird.Mode.REPAIRING
		return SUCCESS

	# 正常到达 rest_area → 开始倒下
	_phase = Phase.SLEEPING_DOWN
	bird.anim_play(&"sleep_down", false, true)
	return RUNNING


func _has_arrived_to_rest(bird: StoneMaskBird) -> bool:
	if bird.target_rest == null:
		return false
	if bird.target_rest.has_method("is_arrived"):
		var by_area: bool = bool(bird.target_rest.call("is_arrived", bird))
		if by_area:
			return true
	return bird.global_position.distance_to(bird.target_rest.global_position) <= bird.reach_rest_px


func _tick_sleeping_down(bird: StoneMaskBird) -> int:
	if bird.anim_is_finished(&"sleep_down"):
		bird.mode = StoneMaskBird.Mode.RESTING
		bird.hp = bird.max_hp
		bird.velocity = Vector2.ZERO
		return SUCCESS
	return RUNNING


func interrupt(actor: Node, blackboard: Blackboard) -> void:
	var bird := actor as StoneMaskBird
	if bird:
		bird.velocity = Vector2.ZERO
		if _phase == Phase.FLYING_TO_REST:
			bird._release_target_rest()
	_phase = Phase.FLYING_TO_REST
	super(actor, blackboard)


func _pick_available_rest_area(bird: StoneMaskBird) -> Node2D:
	var rest_areas := bird.get_tree().get_nodes_in_group("rest_area")
	if rest_areas.is_empty():
		return null
	var candidates: Array[Node2D] = []
	for n in rest_areas:
		var area := n as Node2D
		if area == null:
			continue
		if bird.reserve_rest_area(area):
			candidates.append(area)
			bird.release_rest_area(area)
	if candidates.is_empty():
		return null
	var chosen: Node2D = candidates[randi() % candidates.size()]
	if not bird.reserve_rest_area(chosen):
		return null
	return chosen

func _pick_nearest_break_area(bird: StoneMaskBird) -> Node2D:
	var break_areas := bird.get_tree().get_nodes_in_group("rest_area_break")
	if break_areas.is_empty():
		return null
	var nearest: Node2D = null
	var best_dist: float = INF
	for n in break_areas:
		var area := n as Node2D
		if area == null:
			continue
		var d := bird.global_position.distance_to(area.global_position)
		if d < best_dist:
			best_dist = d
			nearest = area
	return nearest
