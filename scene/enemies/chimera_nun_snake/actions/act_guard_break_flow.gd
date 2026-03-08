extends ActionLeaf
class_name ActNunSnakeGuardBreakFlow

## =============================================================================
## GUARD_BREAK 独立状态处理
## =============================================================================
## 进入时播放 guard_break_enter → guard_break_loop。
## 结束逻辑：
## - 若已进入 WEAK/STUN → 交由对应状态。
## - 否则检测玩家是否在 tail_sweep_range：
##   - 在范围内：open_eye_to_close → tail_sweep_transition → tail_sweep → CLOSED_EYE
##   - 不在范围：直接 open_eye_to_close → CLOSED_EYE
## =============================================================================

enum SubState {
	ENTER = 0,
	LOOP = 1,
	CLOSE_TO_TAIL = 2,     ## open_eye_to_close → tail_sweep_transition → tail_sweep
	CLOSE_ONLY = 3,        ## open_eye_to_close → CLOSED_EYE
	TAIL_TRANSITION = 4,
	TAIL_SWEEP = 5,
}

var _sub_state: int = SubState.ENTER


func before_run(actor: Node, _blackboard: Blackboard) -> void:
	_sub_state = SubState.ENTER
	# guard_break_enter 动画已在 _enter_guard_break 中播放


func tick(actor: Node, _blackboard: Blackboard) -> int:
	var snake: ChimeraNunSnake = actor as ChimeraNunSnake
	if snake == null:
		return FAILURE

	# WEAK/STUN 中断
	if snake.mode == ChimeraNunSnake.Mode.WEAK or snake.mode == ChimeraNunSnake.Mode.STUN:
		return FAILURE

	# 不是 GUARD_BREAK → 退出
	if snake.mode != ChimeraNunSnake.Mode.GUARD_BREAK:
		return SUCCESS

	match _sub_state:
		SubState.ENTER:
			if snake.anim_is_finished(&"guard_break_enter"):
				_sub_state = SubState.LOOP
				snake.anim_play(&"guard_break_loop", true)
			return RUNNING

		SubState.LOOP:
			var now: float = ChimeraNunSnake.now_sec()
			if now >= snake.guard_break_end_sec:
				# 结束：检查玩家距离决定后续
				var target: Node2D = snake.detect_player_in_range(snake.tail_sweep_range)
				if target != null:
					_sub_state = SubState.CLOSE_TO_TAIL
					snake.closing_transition_lock = true
					snake.anim_play(&"open_eye_to_close", false)
				else:
					_sub_state = SubState.CLOSE_ONLY
					snake.closing_transition_lock = true
					snake.anim_play(&"open_eye_to_close", false)
			return RUNNING

		SubState.CLOSE_TO_TAIL:
			if snake.anim_is_finished(&"open_eye_to_close"):
				snake.closing_transition_lock = false
				snake._set_eye_hurtbox_enabled(false)
				# 保持 mode = GUARD_BREAK 直至尾扫结束
				# 提前改 CLOSED_EYE 会使 Cond_ModeGuardBreak 失败，
				# SelectorReactive 会中断此动作导致尾扫永远不会播放
				_sub_state = SubState.TAIL_TRANSITION
				snake.anim_play(&"tail_sweep_transition", false)
			return RUNNING

		SubState.TAIL_TRANSITION:
			if snake.anim_is_finished(&"tail_sweep_transition"):
				_sub_state = SubState.TAIL_SWEEP
				snake.anim_play(&"tail_sweep", false)
			return RUNNING

		SubState.TAIL_SWEEP:
			if snake.anim_is_finished(&"tail_sweep"):
				snake._enter_closed_eye()
				snake.start_attack_cooldown()
				return SUCCESS
			return RUNNING

		SubState.CLOSE_ONLY:
			if snake.anim_is_finished(&"open_eye_to_close"):
				snake.closing_transition_lock = false
				snake._enter_closed_eye()
				snake.start_attack_cooldown()
				return SUCCESS
			return RUNNING

	return RUNNING


func interrupt(actor: Node, blackboard: Blackboard) -> void:
	var snake: ChimeraNunSnake = actor as ChimeraNunSnake
	if snake != null:
		snake.closing_transition_lock = false
		snake.force_close_all_hitboxes()
	_sub_state = SubState.ENTER
	super(actor, blackboard)
