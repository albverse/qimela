extends ActionLeaf
class_name ActReturnToRest

## Act_ReturnToRest（飞行 -> 回巢 -> 倒下）
## 从 RETURN_TO_REST 状态回到休息点。
## 与 ActWakeFlyReturnRest 类似但不需要苏醒/升空阶段（已在空中）。
## 内部阶段：FLYING_TO_REST -> SLEEPING_DOWN
## 完成后：mode=RESTING，HP=3。
## 无可用 rest_area 时：mode=FLYING_ATTACK（避免卡死）。

enum Phase { FLYING_TO_REST, SLEEPING_DOWN }

var _phase: int = Phase.FLYING_TO_REST

func before_run(actor: Node, _blackboard: Blackboard) -> void:
	var bird := actor as StoneMaskBird
	if bird == null:
		return
	_phase = Phase.FLYING_TO_REST

	# 选择可用 rest_area 目标
	var target := bird.pick_available_rest_area()
	if target == null:
		# 无可用 rest_area -> 回到飞行攻击
		bird.mode = StoneMaskBird.Mode.FLYING_ATTACK
		var now := StoneMaskBird.now_sec()
		bird.attack_until_sec = now + bird.attack_duration_sec
		bird.next_attack_sec = now
		return
	bird.target_rest = target
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
		bird.release_rest_area(bird.target_rest)
		bird.target_rest = null
		bird.mode = StoneMaskBird.Mode.FLYING_ATTACK
		return SUCCESS

	var to_rest := bird.target_rest.global_position - bird.global_position
	var dist := to_rest.length()
	var arrive_px := maxf(bird.reach_rest_px, bird.return_speed * dt * 1.25)
	var arrived_by_area := false
	if bird.target_rest.has_method("is_bird_arrived"):
		arrived_by_area = bool(bird.target_rest.call("is_bird_arrived", bird))

	if not arrived_by_area and dist > arrive_px:
		bird.velocity = to_rest.normalized() * bird.return_speed
		bird.move_and_slide()
		return RUNNING

	# 到达 rest_area
	bird.global_position = bird.target_rest.global_position
	bird.velocity = Vector2.ZERO
	_phase = Phase.SLEEPING_DOWN
	bird.anim_play(&"sleep_down", false, true)
	return RUNNING


func _tick_sleeping_down(bird: StoneMaskBird) -> int:
	if bird.anim_is_finished(&"sleep_down"):
		bird.mode = StoneMaskBird.Mode.RESTING
		bird.hp = bird.max_hp
		bird.occupy_rest_area(bird.target_rest)
		bird.target_rest = null
		bird.velocity = Vector2.ZERO
		return SUCCESS
	return RUNNING


func interrupt(actor: Node, blackboard: Blackboard) -> void:
	var bird := actor as StoneMaskBird
	if bird:
		bird.velocity = Vector2.ZERO
		bird.anim_stop_or_blendout()
		bird.release_rest_area(bird.target_rest)
		bird.target_rest = null
	_phase = Phase.FLYING_TO_REST
	super(actor, blackboard)
