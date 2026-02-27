extends ActionLeaf
class_name ActWakeFlyReturnRest

## 7.6 Act_WakeFlyReturnRest（苏醒 -> 升空 -> 回巢 -> 倒下）
## 从 WAKE_FROM_STUN 状态恢复。
## 内部阶段：WAKING -> TAKEOFF -> FLYING_TO_REST -> SLEEPING_DOWN
## 完成后：mode=RESTING，HP=3。
## 无 rest_area 时：直接 mode=FLYING_ATTACK（避免卡死）。

enum Phase { WAKING, TAKEOFF, FLYING_TO_REST, SLEEPING_DOWN }

var _phase: int = Phase.WAKING
var _phase_enter_sec: float = 0.0
var _phase_warned_timeout: bool = false

const _PHASE_TIMEOUT_SEC := {
	Phase.WAKING: 2.0,
	Phase.TAKEOFF: 2.0,
	Phase.FLYING_TO_REST: 8.0,
	Phase.SLEEPING_DOWN: 2.0,
}

const _PHASE_NAME := {
	Phase.WAKING: "WAKING",
	Phase.TAKEOFF: "TAKEOFF",
	Phase.FLYING_TO_REST: "FLYING_TO_REST",
	Phase.SLEEPING_DOWN: "SLEEPING_DOWN",
}

func before_run(actor: Node, _blackboard: Blackboard) -> void:
	var bird := actor as StoneMaskBird
	if bird == null:
		return
	_phase = Phase.WAKING
	_enter_phase(Phase.WAKING)
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
	_check_phase_timeout(bird)
	_ensure_anim_state(bird, &"wake_from_stun", false)
	# 等待苏醒动画完成（复用 wake_up 如果 wake_from_stun 不存在）
	if bird.anim_is_finished(&"wake_from_stun") or bird.anim_is_finished(&"wake_up"):
		_enter_phase(Phase.TAKEOFF)
		bird.anim_play(&"takeoff", false, true)
	return RUNNING


func _tick_takeoff(bird: StoneMaskBird) -> int:
	_check_phase_timeout(bird)
	_ensure_anim_state(bird, &"takeoff", false)
	# 等待升空动画完成（如果没有 takeoff 动画则跳过）
	if bird.anim_is_finished(&"takeoff"):
		_start_fly_to_rest(bird)
	return RUNNING


func _start_fly_to_rest(bird: StoneMaskBird) -> void:
	bird._release_target_rest()
	var rest_area := _pick_available_rest_area(bird)
	if rest_area == null:
		# 无 rest_area -> 回到飞行攻击（避免卡死）
		bird.mode = StoneMaskBird.Mode.FLYING_ATTACK
		var now := StoneMaskBird.now_sec()
		bird.attack_until_sec = now + bird.attack_duration_sec
		bird.next_attack_sec = now
		return
	_enter_phase(Phase.FLYING_TO_REST)
	bird.anim_play(&"fly_move", true, true)


func _tick_flying_to_rest(bird: StoneMaskBird, dt: float) -> int:
	_check_phase_timeout(bird)
	_ensure_anim_state(bird, &"fly_move", true)
	if bird.target_rest == null or not is_instance_valid(bird.target_rest):
		# 目标丢失 -> 回到飞行攻击
		bird._release_target_rest()
		bird.mode = StoneMaskBird.Mode.FLYING_ATTACK
		return SUCCESS

	var to_rest := bird.target_rest.global_position - bird.global_position
	var dist := to_rest.length()

	if dist > bird.reach_rest_px:
		bird.velocity = to_rest.normalized() * bird.return_speed
		bird.move_and_slide()
		return RUNNING

	# 到达 rest_area
	bird.global_position = bird.target_rest.global_position
	bird.velocity = Vector2.ZERO
	_enter_phase(Phase.SLEEPING_DOWN)
	bird.anim_play(&"sleep_down", false, true)
	return RUNNING


func _tick_sleeping_down(bird: StoneMaskBird) -> int:
	_check_phase_timeout(bird)
	_ensure_anim_state(bird, &"sleep_down", false)
	# 等待倒下动画完成（如果没有 sleep_down 动画则立即完成）
	if bird.anim_is_finished(&"sleep_down"):
		_finish_rest(bird)
		return SUCCESS
	return RUNNING


func _finish_rest(bird: StoneMaskBird) -> void:
	bird.mode = StoneMaskBird.Mode.RESTING
	bird.hp = bird.max_hp
	bird.velocity = Vector2.ZERO


func interrupt(actor: Node, blackboard: Blackboard) -> void:
	var bird := actor as StoneMaskBird
	if bird:
		bird.velocity = Vector2.ZERO
		bird.anim_stop_or_blendout()
		if _phase == Phase.FLYING_TO_REST:
			bird._release_target_rest()
	_phase = Phase.WAKING
	_phase_enter_sec = 0.0
	_phase_warned_timeout = false
	super(actor, blackboard)


func _enter_phase(new_phase: int) -> void:
	_phase = new_phase
	_phase_enter_sec = StoneMaskBird.now_sec()
	_phase_warned_timeout = false


func _check_phase_timeout(bird: StoneMaskBird) -> void:
	if _phase_warned_timeout:
		return
	var timeout_sec: float = float(_PHASE_TIMEOUT_SEC.get(_phase, 0.0))
	if timeout_sec <= 0.0:
		return
	var elapsed: float = StoneMaskBird.now_sec() - _phase_enter_sec
	if elapsed < timeout_sec:
		return
	_phase_warned_timeout = true
	var anim_state := bird.anim_debug_state()
	print("[StoneMaskBird][WakeFlyReturn][WARN] phase timeout phase=%s elapsed=%.2f mode=%d anim=%s finished=%s loop=%s target_rest=%s" % [
		str(_PHASE_NAME.get(_phase, "UNKNOWN")),
		elapsed,
		bird.mode,
		str(anim_state.get("name", &"")),
		str(anim_state.get("finished", false)),
		str(anim_state.get("loop", false)),
		str(bird.target_rest),
	])


func _ensure_anim_state(bird: StoneMaskBird, expected_anim: StringName, loop: bool) -> void:
	if bird.anim_is_playing(expected_anim) or bird.anim_is_finished(expected_anim):
		return
	bird.anim_play(expected_anim, loop, true)


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
