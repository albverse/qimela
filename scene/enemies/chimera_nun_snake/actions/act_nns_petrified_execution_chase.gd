extends ActionLeaf
class_name ActNNSPetrifiedExecutionChase

## 石化玩家追击模式（PETRIFIED_EXECUTION_CHASE）。
## 入口：检测到石化玩家且不处于不可中断状态。
## 若当前在 OPEN_EYE / GUARD_BREAK，先关眼再追击。
## 追上后优先执行 tail_sweep 处决。
## 永远返回 RUNNING，直到石化目标消失/解除/追击超时，或自身进入 WEAK/STUN。

enum Phase {
	CLOSING_EYE,   ## 先关眼（若处于睁眼系）
	CHASING,       ## 闭眼追击
	TAIL_SWEEP,    ## 甩尾处决
}

const CHASE_TIMEOUT_MS: int = 10000  ## 追击超时（ms）

var _phase: int = Phase.CHASING
var _chase_start_ms: int = 0
var _sweep_started: bool = false


func before_run(actor: Node, blackboard: Blackboard) -> void:
	var nns := actor as ChimeraNunSnake
	if nns == null:
		return
	_sweep_started = false
	_chase_start_ms = ChimeraNunSnake.now_ms()

	# 若当前睁眼系，先关眼
	if nns.mode == ChimeraNunSnake.Mode.OPEN_EYE or nns.mode == ChimeraNunSnake.Mode.GUARD_BREAK:
		_phase = Phase.CLOSING_EYE
		nns.closing_transition_lock = true
		nns.anim_play(&"open_eye_to_close", false)
	else:
		_phase = Phase.CHASING


func tick(actor: Node, blackboard: Blackboard) -> int:
	var nns := actor as ChimeraNunSnake
	if nns == null:
		return FAILURE

	# WEAK / STUN 中断追击
	if nns.mode == ChimeraNunSnake.Mode.WEAK or nns.mode == ChimeraNunSnake.Mode.STUN:
		return SUCCESS

	var target: Node2D = blackboard.get_value("petrified_target_node") as Node2D
	if target == null or not is_instance_valid(target):
		return SUCCESS  # 目标消失

	# 检查石化是否解除
	if target.has_method("is_petrified") and not target.call("is_petrified"):
		return SUCCESS

	# 追击超时
	if ChimeraNunSnake.now_ms() - _chase_start_ms > CHASE_TIMEOUT_MS:
		return SUCCESS

	match _phase:
		Phase.CLOSING_EYE:
			return _tick_closing_eye(nns)
		Phase.CHASING:
			return _tick_chasing(nns, target)
		Phase.TAIL_SWEEP:
			return _tick_tail_sweep(nns)

	return RUNNING


func _tick_closing_eye(nns: ChimeraNunSnake) -> int:
	var dt := nns.get_physics_process_delta_time()
	nns.velocity.x = 0.0
	nns.velocity.y += 800.0 * dt
	nns.move_and_slide()

	# 等待 open_eye_to_close 完成（Spine 事件 open_to_close_done 或动画完成）
	if nns.ev_open_to_close_done or nns.anim_is_finished(&"open_eye_to_close"):
		nns.ev_open_to_close_done = false
		nns.closing_transition_lock = false
		nns.enter_mode(ChimeraNunSnake.Mode.CLOSED_EYE)
		_phase = Phase.CHASING
	return RUNNING


func _tick_chasing(nns: ChimeraNunSnake, target: Node2D) -> int:
	var dt := nns.get_physics_process_delta_time()
	nns.anim_play(&"closed_eye_run", true)
	nns.mode = ChimeraNunSnake.Mode.CLOSED_EYE

	var h_dist: float = absf(target.global_position.x - nns.global_position.x)
	if h_dist <= nns.tail_sweep_range:
		_phase = Phase.TAIL_SWEEP
		_sweep_started = false
		return RUNNING

	var dir: float = signf(target.global_position.x - nns.global_position.x)
	nns.velocity.x = dir * nns.petrified_target_chase_speed
	nns.velocity.y += 800.0 * dt
	nns.move_and_slide()

	if nns.is_on_wall():
		nns.velocity.x = -nns.velocity.x  # 碰墙掉头（兜底）
	return RUNNING


func _tick_tail_sweep(nns: ChimeraNunSnake) -> int:
	var dt := nns.get_physics_process_delta_time()
	nns.velocity.x = 0.0
	nns.velocity.y += 800.0 * dt
	nns.move_and_slide()

	if not _sweep_started:
		_sweep_started = true
		nns.anim_play(&"tail_sweep", false)

	# 攻击命中窗口由 atk_hit_on/atk_hit_off Spine 事件驱动
	if nns.ev_atk_hit_on:
		nns.ev_atk_hit_on = false
		nns.atk_hit_window_open = true
	if nns.ev_atk_hit_off:
		nns.ev_atk_hit_off = false
		nns.atk_hit_window_open = false

	if nns.anim_is_finished(&"tail_sweep"):
		nns.atk_hit_window_open = false
		return SUCCESS

	return RUNNING


func interrupt(actor: Node, blackboard: Blackboard) -> void:
	var nns := actor as ChimeraNunSnake
	if nns != null:
		nns.velocity = Vector2.ZERO
		nns.force_close_hit_windows()
		nns.closing_transition_lock = false
	super(actor, blackboard)
