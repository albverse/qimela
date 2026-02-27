extends ActionLeaf
class_name ActWakeFlyReturnRest

## 7.6 Act_WakeFlyReturnRest（苏醒 -> 升空 -> 回巢 -> 倒下）
## 从 WAKE_FROM_STUN 状态恢复。
## 内部阶段：WAKING -> TAKEOFF -> FLYING_TO_REST -> SLEEPING_DOWN
## 完成后：mode=RESTING，HP=3。
## 无可用 rest_area 时：直接 mode=FLYING_ATTACK（避免卡死）。

enum Phase { WAKING, TAKEOFF, FLYING_TO_REST, SLEEPING_DOWN }

var _phase: int = Phase.WAKING

func before_run(actor: Node, _blackboard: Blackboard) -> void:
	var bird := actor as StoneMaskBird
	if bird == null:
		return
	_phase = Phase.WAKING
	# 播放苏醒动画（不可打断）
	bird.anim_play(&"wake_from_stun", false, false)


func tick(actor: Node, _blackboard: Blackboard) -> int:
	var bird := actor as StoneMaskBird
	if bird == null:
		return FAILURE

	var dt: float = actor.get_physics_process_delta_time()

	match _phase:
		Phase.WAKING:
			return _tick_waking(bird)
		Phase.TAKEOFF:
			return _tick_takeoff(bird)
		Phase.FLYING_TO_REST:
			return _tick_flying_to_rest(bird, dt)
		Phase.SLEEPING_DOWN:
			return _tick_sleeping_down(bird)
	return RUNNING


func _tick_waking(bird: StoneMaskBird) -> int:
	# 等待苏醒动画完成（复用 wake_up 如果 wake_from_stun 不存在）
	if bird.anim_is_finished(&"wake_from_stun") or bird.anim_is_finished(&"wake_up"):
		_phase = Phase.TAKEOFF
		bird.anim_play(&"takeoff", false, true)
	return RUNNING


func _tick_takeoff(bird: StoneMaskBird) -> int:
	# 等待升空动画完成（如果没有 takeoff 动画则跳过）
	if bird.anim_is_finished(&"takeoff"):
		_start_fly_to_rest(bird)
	return RUNNING


func _start_fly_to_rest(bird: StoneMaskBird) -> void:
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
	_phase = Phase.FLYING_TO_REST
	bird.anim_play(&"fly_move", true, true)


func _tick_flying_to_rest(bird: StoneMaskBird, dt: float) -> int:
	if bird.target_rest == null or not is_instance_valid(bird.target_rest):
		# 目标丢失 -> 回到飞行攻击
		bird.release_rest_area(bird.target_rest)
		bird.target_rest = null
		bird.mode = StoneMaskBird.Mode.FLYING_ATTACK
		return SUCCESS

	var to_rest := bird.target_rest.global_position - bird.global_position
	var dist := to_rest.length()
	# 根因修复：仅用固定 reach_rest_px 容易在高速度下反复擦边，长期 RUNNING。
	# 使用“配置阈值 + 动态刹车阈值”判定到达，避免抖动卡住。
	var arrive_px := maxf(bird.reach_rest_px, bird.return_speed * dt * 1.25)

	if dist > arrive_px:
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
	# 等待倒下动画完成（如果没有 sleep_down 动画则立即完成）
	if bird.anim_is_finished(&"sleep_down"):
		_finish_rest(bird)
		return SUCCESS
	return RUNNING


func _finish_rest(bird: StoneMaskBird) -> void:
	bird.mode = StoneMaskBird.Mode.RESTING
	bird.hp = bird.max_hp
	bird.occupy_rest_area(bird.target_rest)
	bird.target_rest = null
	bird.velocity = Vector2.ZERO


func interrupt(actor: Node, blackboard: Blackboard) -> void:
	var bird := actor as StoneMaskBird
	if bird:
		bird.velocity = Vector2.ZERO
		bird.anim_stop_or_blendout()
		bird.release_rest_area(bird.target_rest)
		bird.target_rest = null
	_phase = Phase.WAKING
	super(actor, blackboard)
