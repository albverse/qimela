extends ActionLeaf
class_name ActNNSGuardBreakFlow

## 破防状态流（GUARD_BREAK）：
##   guard_break_enter → guard_break_loop → [WEAK/STUN 由高优先级接管]
##   or → tail_sweep_transition → tail_sweep → open_eye_to_close → CLOSED_EYE
##   or → open_eye_to_close → CLOSED_EYE
## 属于睁眼系独立状态，拥有专属进入动画与 loop 动画。
## 注意：before_run 每帧被 SelectorReactive 调用（非 running_child 时），
##        需防止重复初始化；使用 _initialized 标志保护。

enum Phase {
	ENTER,                ## 播放 guard_break_enter
	LOOP,                 ## 播放 guard_break_loop（等待计时结束）
	TAIL_SWEEP_TRANSITION,## 关眼前的 tail_sweep_transition
	TAIL_SWEEP,           ## 甩尾处决
	CLOSING,              ## 播放 open_eye_to_close
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
		Phase.TAIL_SWEEP_TRANSITION:
			return _tick_tail_sweep_transition(nns)
		Phase.TAIL_SWEEP:
			return _tick_tail_sweep(nns)
		Phase.CLOSING:
			return _tick_closing(nns)

	return RUNNING


func _tick_enter(nns: ChimeraNunSnake) -> int:
	## guard_break_enter 结束后进入 guard_break_loop
	if nns.ev_guard_break_enter_done or nns.anim_is_finished(&"guard_break_enter"):
		nns.ev_guard_break_enter_done = false
		_phase = Phase.LOOP
		nns.anim_play(&"guard_break_loop", true)
	return RUNNING


func _tick_loop(nns: ChimeraNunSnake) -> int:
	## 等待破防计时结束（Spine guard_break_enter_done 事件已在 ENTER 阶段消耗，
	## 这里用时间计时器）
	var timed_out: bool = ChimeraNunSnake.now_ms() >= nns.guard_break_end_ms
	if timed_out:
		_decide_exit(nns)
	return RUNNING


func _decide_exit(nns: ChimeraNunSnake) -> void:
	## 根据玩家距离决定是否先 tail_sweep_transition → tail_sweep
	if not _sweep_attempted and nns.is_player_in_range(nns.tail_sweep_range):
		_sweep_attempted = true
		_phase = Phase.TAIL_SWEEP_TRANSITION
		nns.anim_play(&"tail_sweep_transition", false)
	else:
		_phase = Phase.CLOSING
		nns.closing_transition_lock = true
		nns.anim_play(&"open_eye_to_close", false)


func _tick_tail_sweep_transition(nns: ChimeraNunSnake) -> int:
	## 等待 tail_sweep_transition 完成（Spine 事件 tail_sweep_transition_done 或动画结束）
	if nns.ev_tail_sweep_transition_done or nns.anim_is_finished(&"tail_sweep_transition"):
		nns.ev_tail_sweep_transition_done = false
		_phase = Phase.TAIL_SWEEP
		nns.anim_play(&"tail_sweep", false)
	return RUNNING


func _tick_tail_sweep(nns: ChimeraNunSnake) -> int:
	if nns.ev_atk_hit_on:
		nns.ev_atk_hit_on = false
		nns.atk_hit_window_open = true
		if nns._tail_sweep_hitbox != null:
			nns._tail_sweep_hitbox.monitoring = true
	if nns.ev_atk_hit_off:
		nns.ev_atk_hit_off = false
		nns.atk_hit_window_open = false
		if nns._tail_sweep_hitbox != null:
			nns._tail_sweep_hitbox.monitoring = false

	if nns.anim_is_finished(&"tail_sweep"):
		nns.atk_hit_window_open = false
		if nns._tail_sweep_hitbox != null:
			nns._tail_sweep_hitbox.monitoring = false
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
		if nns._tail_sweep_hitbox != null:
			nns._tail_sweep_hitbox.monitoring = false
	super(actor, blackboard)
