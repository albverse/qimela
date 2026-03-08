extends ActionLeaf
class_name ActNunSnakeClosedEyeIntent

## =============================================================================
## CLOSED_EYE 闭眼反应逻辑
## =============================================================================
## 感知到目标后，选择意图：
## - stiff_attack → 进入 OPEN_EYE 攻击链（close_to_open → stiff_attack → ...）
## - ground_pound → 保持 CLOSED_EYE，直接执行 ground_pound
##
## 意图选择规则：
## - 玩家在 stiff_attack_range → 选 stiff_attack（进入攻击链）
## - 玩家在 ground_pound_range → 选 ground_pound
## - 否则 → 闭眼移动接近
## =============================================================================

enum SubState {
	SELECTING = 0,
	WALKING = 1,
	GROUND_POUND = 2,
	OPEN_EYE_CHAIN = 3,  ## 切到 OpenEyeAttackChain action
}

var _sub_state: int = SubState.SELECTING


func before_run(actor: Node, _blackboard: Blackboard) -> void:
	_sub_state = SubState.SELECTING


func tick(actor: Node, blackboard: Blackboard) -> int:
	var snake: ChimeraNunSnake = actor as ChimeraNunSnake
	if snake == null:
		return FAILURE

	if snake.mode != ChimeraNunSnake.Mode.CLOSED_EYE:
		return FAILURE

	var target: Node2D = blackboard.get_value("target_node") as Node2D
	if target == null or not is_instance_valid(target):
		target = snake.detect_player_in_range(snake.detect_player_radius)
		if target == null:
			snake.velocity = Vector2.ZERO
			return FAILURE

	match _sub_state:
		SubState.SELECTING:
			return _tick_select(snake, target)
		SubState.WALKING:
			return _tick_walking(snake, target)
		SubState.GROUND_POUND:
			return _tick_ground_pound(snake)

	return RUNNING


func _tick_select(snake: ChimeraNunSnake, target: Node2D) -> int:
	var h_dist: float = abs(target.global_position.x - snake.global_position.x)

	# 在 stiff_attack_range → 选择开眼攻击链（交由 ActOpenEyeAttackChain 处理）
	if h_dist <= snake.stiff_attack_range:
		snake.face_toward(target)
		return SUCCESS  # SUCCESS 让 Selector 进入下一个分支（OpenEye）

	# 在 ground_pound_range → 闭眼锤地
	if h_dist <= snake.ground_pound_range:
		snake.face_toward(target)
		_sub_state = SubState.GROUND_POUND
		snake.anim_play(&"ground_pound", false)
		return RUNNING

	# 不在范围 → 闭眼行走接近
	_sub_state = SubState.WALKING
	snake.anim_play(&"closed_eye_walk", true)
	return RUNNING


func _tick_walking(snake: ChimeraNunSnake, target: Node2D) -> int:
	var h_dist: float = abs(target.global_position.x - snake.global_position.x)

	# 到达攻击范围 → 重新选择
	if h_dist <= snake.stiff_attack_range:
		snake.velocity = Vector2.ZERO
		_sub_state = SubState.SELECTING
		return _tick_select(snake, target)

	if h_dist <= snake.ground_pound_range:
		snake.velocity = Vector2.ZERO
		_sub_state = SubState.SELECTING
		return _tick_select(snake, target)

	# 移动
	snake.face_toward(target)
	var dir_x: float = sign(target.global_position.x - snake.global_position.x)
	snake.velocity.x = dir_x * snake.closed_walk_speed
	snake.velocity.y += snake.get_physics_process_delta_time() * 1500.0  # gravity
	snake.move_and_slide()
	return RUNNING


func _tick_ground_pound(snake: ChimeraNunSnake) -> int:
	snake.velocity = Vector2.ZERO
	if snake.anim_is_finished(&"ground_pound"):
		snake.force_close_all_hitboxes()
		_sub_state = SubState.SELECTING
		snake.anim_play(&"closed_eye_idle", true)
		return SUCCESS
	return RUNNING


func interrupt(actor: Node, blackboard: Blackboard) -> void:
	var snake: ChimeraNunSnake = actor as ChimeraNunSnake
	if snake != null:
		snake.velocity = Vector2.ZERO
		snake.force_close_all_hitboxes()
	_sub_state = SubState.SELECTING
	super(actor, blackboard)
