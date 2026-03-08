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
##
## 攻击之间有冷却期（attack_cooldown_sec），冷却中继续行走接近。
## =============================================================================

enum SubState {
	SELECTING = 0,
	WALKING = 1,
	GROUND_POUND = 2,
	COOLDOWN_WALK = 3,  ## 攻击冷却中，继续行走
	POST_STUN_TAIL_TRANSITION = 4,  ## STUN 恢复后玩家在场，立即尾扫
	POST_STUN_TAIL_SWEEP = 5,
}

var _sub_state: int = SubState.SELECTING


func before_run(actor: Node, _blackboard: Blackboard) -> void:
	var snake: ChimeraNunSnake = actor as ChimeraNunSnake
	if snake == null:
		_sub_state = SubState.SELECTING
		return
	# 检查 STUN 恢复后的尾扫请求
	if snake.post_stun_tail_sweep_requested:
		snake.post_stun_tail_sweep_requested = false
		_sub_state = SubState.POST_STUN_TAIL_TRANSITION
		snake.anim_play(&"tail_sweep_transition", false)
	else:
		_sub_state = SubState.SELECTING


func tick(actor: Node, blackboard: Blackboard) -> int:
	var snake: ChimeraNunSnake = actor as ChimeraNunSnake
	if snake == null:
		return FAILURE

	if snake.mode != ChimeraNunSnake.Mode.CLOSED_EYE:
		return FAILURE

	# STUN 恢复尾扫（不需要玩家在范围内，直接执行）
	if _sub_state == SubState.POST_STUN_TAIL_TRANSITION:
		return _tick_post_stun_tail_transition(snake)
	if _sub_state == SubState.POST_STUN_TAIL_SWEEP:
		return _tick_post_stun_tail_sweep(snake)

	var target: Node2D = blackboard.get_value("target_node") as Node2D
	if target == null or not is_instance_valid(target):
		target = snake.detect_player_in_range(snake.detect_player_radius)
		if target == null:
			snake.velocity.x = 0.0
			return FAILURE

	match _sub_state:
		SubState.SELECTING:
			return _tick_select(snake, target)
		SubState.WALKING:
			return _tick_walking(snake, target)
		SubState.GROUND_POUND:
			return _tick_ground_pound(snake)
		SubState.COOLDOWN_WALK:
			return _tick_cooldown_walk(snake, target)

	return RUNNING


func _tick_select(snake: ChimeraNunSnake, target: Node2D) -> int:
	var h_dist: float = abs(target.global_position.x - snake.global_position.x)

	# 冷却中 → 行走接近（不发动攻击）
	if snake.is_attack_on_cooldown():
		_sub_state = SubState.COOLDOWN_WALK
		snake.anim_play(&"closed_eye_walk", true)
		return RUNNING

	# 在 stiff_attack_range → 选择开眼攻击链（交由 ActOpenEyeAttackChain 处理）
	if h_dist <= snake.stiff_attack_range:
		snake.face_toward(target)
		# 预设 mode=OPEN_EYE，使 Seq_OpenEyeAttack 的 Cond_ModeOpenEye 在下一帧通过
		snake.mode = ChimeraNunSnake.Mode.OPEN_EYE
		return SUCCESS

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
		snake.velocity.x = 0.0
		_sub_state = SubState.SELECTING
		return _tick_select(snake, target)

	if h_dist <= snake.ground_pound_range:
		snake.velocity.x = 0.0
		_sub_state = SubState.SELECTING
		return _tick_select(snake, target)

	# 移动
	snake.face_toward(target)
	var dir_x: float = sign(target.global_position.x - snake.global_position.x)
	snake.velocity.x = dir_x * snake.closed_walk_speed
	# gravity + move_and_slide handled by chimera_nun_snake._physics_process
	return RUNNING


func _tick_ground_pound(snake: ChimeraNunSnake) -> int:
	snake.velocity.x = 0.0
	if snake.anim_is_finished(&"ground_pound"):
		snake.force_close_all_hitboxes()
		# 攻击结束 → 启动冷却，进入冷却行走
		snake.start_attack_cooldown()
		_sub_state = SubState.COOLDOWN_WALK
		snake.anim_play(&"closed_eye_walk", true)
		return RUNNING
	return RUNNING


func _tick_cooldown_walk(snake: ChimeraNunSnake, target: Node2D) -> int:
	# 冷却结束 → 重新选择攻击
	if not snake.is_attack_on_cooldown():
		snake.velocity.x = 0.0
		_sub_state = SubState.SELECTING
		return _tick_select(snake, target)

	# 冷却中继续向玩家行走（使怪物有机会走入 stiff_attack_range）
	snake.face_toward(target)
	var dir_x: float = sign(target.global_position.x - snake.global_position.x)
	snake.velocity.x = dir_x * snake.closed_walk_speed
	return RUNNING


func _tick_post_stun_tail_transition(snake: ChimeraNunSnake) -> int:
	snake.velocity.x = 0.0
	if snake.anim_is_finished(&"tail_sweep_transition"):
		_sub_state = SubState.POST_STUN_TAIL_SWEEP
		snake.anim_play(&"tail_sweep", false)
	return RUNNING


func _tick_post_stun_tail_sweep(snake: ChimeraNunSnake) -> int:
	snake.velocity.x = 0.0
	if snake.anim_is_finished(&"tail_sweep"):
		snake.force_close_all_hitboxes()
		snake.start_attack_cooldown()
		return SUCCESS
	return RUNNING


func interrupt(actor: Node, blackboard: Blackboard) -> void:
	var snake: ChimeraNunSnake = actor as ChimeraNunSnake
	if snake != null:
		snake.velocity.x = 0.0
		snake.force_close_all_hitboxes()
		snake.post_stun_tail_sweep_requested = false
	_sub_state = SubState.SELECTING
	super(actor, blackboard)
