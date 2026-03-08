extends ActionLeaf
class_name ActNunSnakeOpenEyeAttackChain

## =============================================================================
## OPEN_EYE 固定攻击链
## =============================================================================
## close_to_open → stiff_attack → open_eye_idle (timeout) →
## shoot_eye_start → shoot_eye_loop → shoot_eye_end →
## open_eye_to_close → CLOSED_EYE
##
## 除非中途被 WEAK/STUN 打断。
## =============================================================================

enum SubState {
	CLOSE_TO_OPEN,
	STIFF_ATTACK,
	STIFF_ATTACK_COUNTER_CLOSE,
	STIFF_ATTACK_COUNTER_TAIL_TRANSITION,
	STIFF_ATTACK_COUNTER_TAIL_SWEEP,
	OPEN_EYE_IDLE,
	SHOOT_EYE_START,
	SHOOT_EYE_LOOP,
	SHOOT_EYE_END,
	OPEN_EYE_TO_CLOSE,
}

var _sub_state: int = SubState.CLOSE_TO_OPEN
var _idle_start_sec: float = 0.0
## 是否已发射眼球（防止重复）
var _eye_shot_spawned: bool = false


func before_run(actor: Node, _blackboard: Blackboard) -> void:
	var snake: ChimeraNunSnake = actor as ChimeraNunSnake
	if snake == null:
		return
	_sub_state = SubState.CLOSE_TO_OPEN
	_idle_start_sec = 0.0
	_eye_shot_spawned = false
	snake.opening_transition_lock = true
	snake.anim_play(&"close_to_open", false)


func tick(actor: Node, _blackboard: Blackboard) -> int:
	var snake: ChimeraNunSnake = actor as ChimeraNunSnake
	if snake == null:
		return FAILURE

	# WEAK/STUN 中断
	if snake.mode == ChimeraNunSnake.Mode.WEAK or snake.mode == ChimeraNunSnake.Mode.STUN:
		return FAILURE

	snake.velocity.x = 0.0

	match _sub_state:
		SubState.CLOSE_TO_OPEN:
			if snake.anim_is_finished(&"close_to_open"):
				snake.opening_transition_lock = false
				snake._enter_open_eye()
				_sub_state = SubState.STIFF_ATTACK
				snake._stiff_eye_hit_tail_counter_requested = false
				snake.anim_play(&"stiff_attack", false)
			return RUNNING

		SubState.STIFF_ATTACK:
			if snake.consume_stiff_eye_hit_tail_counter_request():
				snake.closing_transition_lock = true
				_sub_state = SubState.STIFF_ATTACK_COUNTER_CLOSE
				snake.anim_play(&"open_eye_to_close", false)
				return RUNNING
			if snake.anim_is_finished(&"stiff_attack"):
				_sub_state = SubState.OPEN_EYE_IDLE
				_idle_start_sec = ChimeraNunSnake.now_sec()
				snake.anim_play(&"open_eye_idle", true)
			return RUNNING

		SubState.STIFF_ATTACK_COUNTER_CLOSE:
			if snake.anim_is_finished(&"open_eye_to_close"):
				snake.closing_transition_lock = false
				# 仅关闭 EyeHurtbox，保持 mode = OPEN_EYE 直至尾扫结束
				# 提前调用 _enter_closed_eye() 会使 Cond_ModeOpenEye 失败，
				# SelectorReactive 会中断此动作导致 tail_sweep 永远不会播放
				snake._set_eye_hurtbox_enabled(false)
				_sub_state = SubState.STIFF_ATTACK_COUNTER_TAIL_TRANSITION
				snake.anim_play(&"tail_sweep_transition", false)
			return RUNNING

		SubState.STIFF_ATTACK_COUNTER_TAIL_TRANSITION:
			if snake.anim_is_finished(&"tail_sweep_transition"):
				_sub_state = SubState.STIFF_ATTACK_COUNTER_TAIL_SWEEP
				snake.anim_play(&"tail_sweep", false)
			return RUNNING

		SubState.STIFF_ATTACK_COUNTER_TAIL_SWEEP:
			if snake.anim_is_finished(&"tail_sweep"):
				snake._enter_closed_eye()  # 尾扫完成后才切换到 CLOSED_EYE
				snake.start_attack_cooldown()
				return SUCCESS
			return RUNNING

		SubState.OPEN_EYE_IDLE:
			var elapsed: float = ChimeraNunSnake.now_sec() - _idle_start_sec
			if elapsed >= snake.open_eye_idle_timeout:
				_sub_state = SubState.SHOOT_EYE_START
				snake.anim_play(&"shoot_eye_start", false)
			return RUNNING

		SubState.SHOOT_EYE_START:
			# eye_shoot_spawn 事件会在此动画中触发
			if snake.anim_is_finished(&"shoot_eye_start"):
				_sub_state = SubState.SHOOT_EYE_LOOP
				snake.anim_play(&"shoot_eye_loop", true)
			return RUNNING

		SubState.SHOOT_EYE_LOOP:
			# 等待眼球返航
			if snake.eye_phase == ChimeraNunSnake.EyePhase.SOCKETED:
				_sub_state = SubState.SHOOT_EYE_END
				snake.anim_play(&"shoot_eye_end", false)
			return RUNNING

		SubState.SHOOT_EYE_END:
			if snake.anim_is_finished(&"shoot_eye_end"):
				_sub_state = SubState.OPEN_EYE_TO_CLOSE
				snake.closing_transition_lock = true
				snake.anim_play(&"open_eye_to_close", false)
			return RUNNING

		SubState.OPEN_EYE_TO_CLOSE:
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
		snake.opening_transition_lock = false
		snake.closing_transition_lock = false
		snake.force_close_all_hitboxes()
	_sub_state = SubState.CLOSE_TO_OPEN
	_eye_shot_spawned = false
	super(actor, blackboard)
