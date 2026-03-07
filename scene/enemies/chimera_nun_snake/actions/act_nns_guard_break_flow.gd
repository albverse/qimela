extends ActionLeaf
class_name ActNNSGuardBreakFlow

## 破防状态流（GUARD_BREAK）：
##   guard_break_enter → guard_break_loop → [WEAK/STUN] 或 tail_sweep → 关眼 → CLOSED_EYE
## 属于睁眼系独立状态，拥有专属进入动画与 loop 动画。

enum Phase {
	ENTER,      ## 播放 guard_break_enter
	LOOP,       ## 播放 guard_break_loop（等待计时结束）
	TAIL_SWEEP, ## 关眼前可选的甩尾
	CLOSING,    ## 播放 open_eye_to_close
}

var _phase: int = Phase.ENTER
var _sweep_attempted: bool = false


func before_run(actor: Node, _blackboard: Blackboard) -> void:
	var nns := actor as ChimeraNunSnake
	if nns == null:
		return
	_phase = Phase.ENTER
	_sweep_attempted = false
	nns.anim_play(&"guard_break_enter", false)


func tick(actor: Node, _blackboard: Blackboard) -> int:
	var nns := actor as ChimeraNunSnake
	if nns == null:
		return FAILURE

	# WEAK / STUN 优先退出（由 RootSelector 上方分支处理）
	if nns.mode == ChimeraNunSnake.Mode.WEAK or nns.mode == ChimeraNunSnake.Mode.STUN:
		return SUCCESS

	var dt := nns.get_physics_process_delta_time()
	nns.velocity.x = 0.0
	nns.velocity.y += 800.0 * dt
	nns.move_and_slide()

	match _phase:
		Phase.ENTER:
			return _tick_enter(nns)
		Phase.LOOP:
			return _tick_loop(nns)
		Phase.TAIL_SWEEP:
			return _tick_tail_sweep(nns)
		Phase.CLOSING:
			return _tick_closing(nns)

	return RUNNING


func _tick_enter(nns: ChimeraNunSnake) -> int:
	if nns.anim_is_finished(&"guard_break_enter"):
		_phase = Phase.LOOP
		nns.anim_play(&"guard_break_loop", true)
	return RUNNING


func _tick_loop(nns: ChimeraNunSnake) -> int:
	# 等待破防计时结束（guard_break_done Spine 事件 或 计时器）
	var timed_out: bool = ChimeraNunSnake.now_ms() >= nns.guard_break_end_ms
	if nns.ev_guard_break_done or timed_out:
		nns.ev_guard_break_done = false
		_decide_exit(nns)
	return RUNNING


func _decide_exit(nns: ChimeraNunSnake) -> void:
	## 根据玩家距离决定是否先 tail_sweep
	if not _sweep_attempted and nns.is_player_in_range(nns.tail_sweep_range):
		_sweep_attempted = true
		_phase = Phase.TAIL_SWEEP
		nns.anim_play(&"tail_sweep", false)
	else:
		_phase = Phase.CLOSING
		nns.closing_transition_lock = true
		nns.anim_play(&"open_eye_to_close", false)


func _tick_tail_sweep(nns: ChimeraNunSnake) -> int:
	if nns.ev_atk_hit_on:
		nns.ev_atk_hit_on = false
		nns.atk_hit_window_open = true
	if nns.ev_atk_hit_off:
		nns.ev_atk_hit_off = false
		nns.atk_hit_window_open = false

	if nns.anim_is_finished(&"tail_sweep"):
		nns.atk_hit_window_open = false
		_phase = Phase.CLOSING
		nns.closing_transition_lock = true
		nns.anim_play(&"open_eye_to_close", false)
	return RUNNING


func _tick_closing(nns: ChimeraNunSnake) -> int:
	if nns.ev_open_to_close_done or nns.anim_is_finished(&"open_eye_to_close"):
		nns.ev_open_to_close_done = false
		nns.closing_transition_lock = false
		nns.enter_mode(ChimeraNunSnake.Mode.CLOSED_EYE)
		return SUCCESS
	return RUNNING


func interrupt(actor: Node, blackboard: Blackboard) -> void:
	var nns := actor as ChimeraNunSnake
	if nns != null:
		nns.velocity = Vector2.ZERO
		nns.force_close_hit_windows()
		nns.closing_transition_lock = false
	super(actor, blackboard)
