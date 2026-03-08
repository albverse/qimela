extends ActionLeaf
class_name ActNunSnakePetrifiedExecutionChase

## =============================================================================
## PETRIFIED_EXECUTION_CHASE — 石化追击模式
## =============================================================================
## 检测到石化玩家后，使用闭眼高速移动追击。
## 进入 tail_sweep_range 后执行 tail_sweep_transition → tail_sweep。
## 若当前在 OPEN_EYE/GUARD_BREAK，需先关眼再追击。
## =============================================================================

enum SubState {
	CLOSING_EYE = 0,
	CHASING = 1,
	TAIL_SWEEP_TRANSITION = 2,
	TAIL_SWEEP = 3,
}

var _sub_state: int = SubState.CHASING
var _chase_timeout: float = 8.0
var _chase_timer: float = 0.0


func before_run(actor: Node, _blackboard: Blackboard) -> void:
	var snake: ChimeraNunSnake = actor as ChimeraNunSnake
	if snake == null:
		return
	_chase_timer = 0.0

	# 若当前是睁眼系，先关眼
	if snake.mode == ChimeraNunSnake.Mode.OPEN_EYE or snake.mode == ChimeraNunSnake.Mode.GUARD_BREAK:
		_sub_state = SubState.CLOSING_EYE
		snake.closing_transition_lock = true
		snake.anim_play(&"open_eye_to_close", false)
	else:
		_sub_state = SubState.CHASING
		snake.mode = ChimeraNunSnake.Mode.CLOSED_EYE
		snake.anim_play(&"closed_eye_run", true)


func tick(actor: Node, _blackboard: Blackboard) -> int:
	var snake: ChimeraNunSnake = actor as ChimeraNunSnake
	if snake == null:
		return FAILURE

	# 检查 WEAK/STUN 中断
	if snake.mode == ChimeraNunSnake.Mode.WEAK or snake.mode == ChimeraNunSnake.Mode.STUN:
		return FAILURE

	var target: Node2D = snake.petrified_target_node
	if target == null or not is_instance_valid(target):
		snake.velocity.x = 0.0
		return SUCCESS  # 目标丢失

	# 检查目标是否仍然石化
	if target.has_method("is_petrified") and not target.call("is_petrified"):
		snake.velocity.x = 0.0
		return SUCCESS

	match _sub_state:
		SubState.CLOSING_EYE:
			return _tick_closing_eye(snake, target)
		SubState.CHASING:
			return _tick_chasing(snake, target)
		SubState.TAIL_SWEEP_TRANSITION:
			return _tick_tail_sweep_transition(snake)
		SubState.TAIL_SWEEP:
			return _tick_tail_sweep(snake)

	return RUNNING


func _tick_closing_eye(snake: ChimeraNunSnake, _target: Node2D) -> int:
	if snake.anim_is_finished(&"open_eye_to_close"):
		snake.closing_transition_lock = false
		snake._enter_closed_eye()
		_sub_state = SubState.CHASING
		snake.anim_play(&"closed_eye_run", true)
	return RUNNING


func _tick_chasing(snake: ChimeraNunSnake, target: Node2D) -> int:
	_chase_timer += snake.get_physics_process_delta_time()
	if _chase_timer >= _chase_timeout:
		snake.velocity.x = 0.0
		return SUCCESS  # 追击超时

	snake.face_toward(target)

	# 检查是否进入 tail_sweep_range
	var h_dist: float = abs(target.global_position.x - snake.global_position.x)
	if h_dist <= snake.tail_sweep_range:
		snake.velocity.x = 0.0
		_sub_state = SubState.TAIL_SWEEP_TRANSITION
		snake.anim_play(&"tail_sweep_transition", false)
		return RUNNING

	# 闭眼高速追击
	var dir_x: float = sign(target.global_position.x - snake.global_position.x)
	snake.velocity.x = dir_x * snake.petrified_target_chase_speed
	# gravity + move_and_slide handled by chimera_nun_snake._physics_process
	return RUNNING


func _tick_tail_sweep_transition(snake: ChimeraNunSnake) -> int:
	snake.velocity.x = 0.0
	if snake.anim_is_finished(&"tail_sweep_transition"):
		_sub_state = SubState.TAIL_SWEEP
		snake.anim_play(&"tail_sweep", false)
	return RUNNING


func _tick_tail_sweep(snake: ChimeraNunSnake) -> int:
	snake.velocity.x = 0.0
	if snake.anim_is_finished(&"tail_sweep"):
		snake._enter_closed_eye()
		return SUCCESS
	return RUNNING


func interrupt(actor: Node, blackboard: Blackboard) -> void:
	var snake: ChimeraNunSnake = actor as ChimeraNunSnake
	if snake != null:
		snake.velocity.x = 0.0
		snake.closing_transition_lock = false
		snake.force_close_all_hitboxes()
	_sub_state = SubState.CHASING
	_chase_timer = 0.0
	super(actor, blackboard)
