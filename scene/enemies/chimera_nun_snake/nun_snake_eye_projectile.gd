extends Area2D
class_name NunSnakeEyeProjectile

## =============================================================================
## NunSnakeEyeProjectile — 修女蛇眼球子弹
## =============================================================================
## 独立实例场景，不走普通 projectile 伤害路由。
## 行为：飞向玩家 → 悬停 → 重新锁定 → 重复 N 次 → 正常返航 → 销毁。
## 命中玩家 → 进入 PETRIFIED。
## 不可被任何攻击命中，不参与普通地面刚体碰撞。
## =============================================================================

enum Phase {
	OUTBOUND = 0,    ## 飞向目标
	HOVER = 1,       ## 悬停
	RETARGET = 2,    ## 重新锁定后飞行
	RETURNING = 3,   ## 正常返航
	FORCE_RECALL = 4, ## 强制返航（WEAK/STUN 触发）
}

var _phase: int = Phase.OUTBOUND
var _target: Node2D = null
var _owner_snake: Node2D = null
var _speed: float = 250.0
var _retarget_count: int = 3
var _return_speed: float = 700.0
var _max_lifetime_sec: float = 20.0
var _curve_amplitude: float = 180.0
var _curve_cycles: float = 2.0
var _curve_segment_length_px: float = 520.0
var _accel_exponent: float = 2.0
var _linear_decel_distance_px: float = 100.0
var _linear_decel_speed: float = 520.0

var _remaining_retargets: int = 0
var _lifetime_timer: float = 0.0
var _target_pos: Vector2 = Vector2.ZERO
var _done: bool = false
var _velocity: Vector2 = Vector2.ZERO
var _segment_start: Vector2 = Vector2.ZERO
var _segment_end: Vector2 = Vector2.ZERO
var _segment_len: float = 0.0
var _segment_progress: float = 0.0
var _curve_sign: float = 1.0
var _segment_wave_scale: float = 1.0
var _is_linear_decel_mode: bool = false
var _segment_elapsed_sec: float = 0.0
var _segment_duration_sec: float = 0.0
var _curve_segment_index: int = 0
var _segment_curve_amplitude: float = 0.0

const CURVE_FAST_PHASE_TIME_RATIO: float = 0.78
const CURVE_FAST_PHASE_DISPLACEMENT_RATIO: float = 0.88


func setup(
	target: Node2D,
	owner_snake: Node2D,
	speed: float,
	retarget_count: int,
	return_speed: float,
	max_lifetime_sec: float,
	curve_amplitude: float = 180.0,
	curve_cycles: float = 2.0,
	curve_segment_length_px: float = 520.0,
	accel_exponent: float = 2.0,
	linear_decel_distance_px: float = 100.0,
	linear_decel_speed: float = 520.0
) -> void:
	_target = target
	_owner_snake = owner_snake
	_speed = speed
	_retarget_count = retarget_count
	_remaining_retargets = retarget_count
	_return_speed = return_speed
	_max_lifetime_sec = max_lifetime_sec
	_curve_amplitude = max(curve_amplitude, 0.0)
	_curve_cycles = max(curve_cycles, 0.0)
	_curve_segment_length_px = max(curve_segment_length_px, 0.0)
	_accel_exponent = max(accel_exponent, 0.01)
	_linear_decel_distance_px = max(linear_decel_distance_px, 0.0)
	_linear_decel_speed = max(linear_decel_speed, 1.0)
	_curve_segment_index = 0

	if not _start_next_attack_segment(true):
		_start_return()
		return


func force_recall() -> void:
	## 由修女蛇进入 WEAK/STUN 时调用
	_phase = Phase.FORCE_RECALL


func _ready() -> void:
	# 眼球不可被任何攻击命中：collision_layer = 0
	# 检测玩家碰触：collision_mask = 2 (PlayerBody(2))
	collision_layer = 0  # 不可被命中
	collision_mask = 2  # PlayerBody(2) / Inspector 第2层

	body_entered.connect(_on_body_entered)


func _physics_process(dt: float) -> void:
	if _done:
		return

	_lifetime_timer += dt

	# 兜底超时
	if _lifetime_timer >= _max_lifetime_sec:
		_destroy_self()
		return

	match _phase:
		Phase.OUTBOUND, Phase.RETARGET:
			_process_fly(dt)
		Phase.RETURNING:
			_process_return(dt)
		Phase.FORCE_RECALL:
			_process_force_recall(dt)


func _process_fly(dt: float) -> void:
	# 飞行模式在每段路径开始时确定，避免阈值附近逐帧切换造成曲线路径漂移
	# 抛物线段使用固定总时长前快后慢曲线，近身直线段保持原指数减速逻辑
	if _advance_segment(dt):
		global_position = _target_pos
		if _remaining_retargets > 0:
			if not _start_next_attack_segment(false):
				_start_return()
		else:
			_start_return()



func _refresh_segment_motion_mode(use_linear_decel: bool) -> void:
	_is_linear_decel_mode = use_linear_decel
	_segment_wave_scale = 0.0 if use_linear_decel else 1.0



func _start_next_attack_segment(is_initial: bool) -> bool:
	if _target == null or not is_instance_valid(_target):
		return false

	var target_pos: Vector2 = _target.global_position
	var to_target: Vector2 = target_pos - global_position
	var distance_to_target: float = to_target.length()
	if distance_to_target <= 0.001:
		return false

	var dir: Vector2 = to_target / distance_to_target
	if distance_to_target < _linear_decel_distance_px:
		# 直线模式：终点延长到“眼球->玩家”距离的 2 倍位置
		var linear_end: Vector2 = global_position + dir * distance_to_target * 2.0
		_begin_motion_segment(linear_end, 0.0, false)
		_refresh_segment_motion_mode(true)
	else:
		# 曲线模式：每段固定消耗抛物线长度；若玩家过远超出可达长度则直接返航
		if distance_to_target > _curve_segment_length_px:
			return false
		var curve_end: Vector2 = global_position + dir * _curve_segment_length_px
		_begin_motion_segment(curve_end, 1.0, true)
		_curve_segment_index += 1
		_segment_curve_amplitude = _curve_amplitude * pow(0.5, float(_curve_segment_index - 1))
		_refresh_segment_motion_mode(false)

	if is_initial:
		_phase = Phase.OUTBOUND
	else:
		_phase = Phase.RETARGET
		_remaining_retargets -= 1
		if _owner_snake != null and is_instance_valid(_owner_snake):
			_owner_snake.eye_phase = ChimeraNunSnake.EyePhase.RETARGETING
	return true


func _start_return() -> void:
	_phase = Phase.RETURNING
	if _owner_snake != null and is_instance_valid(_owner_snake):
		_owner_snake.eye_phase = ChimeraNunSnake.EyePhase.RETURNING


func _process_return(dt: float) -> void:
	# 返航保持直线，避免曲线路径在移动目标附近产生异常
	var return_pos: Vector2 = _get_return_position()
	var dir: Vector2 = global_position.direction_to(return_pos)
	global_position += dir * _return_speed * dt

	if global_position.distance_to(return_pos) <= 15.0:
		_on_returned()


func _process_force_recall(dt: float) -> void:
	# 强制召回同样使用直线返航，但速度更快
	var return_pos: Vector2 = _get_return_position()
	var dir: Vector2 = global_position.direction_to(return_pos)
	global_position += dir * _return_speed * 1.5 * dt

	if global_position.distance_to(return_pos) <= 15.0:
		_on_returned()


func _begin_motion_segment(target_pos: Vector2, wave_scale: float, flip_curve: bool) -> void:
	_segment_start = global_position
	_segment_end = target_pos
	_target_pos = target_pos
	_segment_len = _segment_start.distance_to(_segment_end)
	_segment_progress = 0.0
	_segment_elapsed_sec = 0.0
	_segment_wave_scale = max(wave_scale, 0.0)
	_segment_duration_sec = _segment_len / max(_speed, 1.0)
	_segment_curve_amplitude = 0.0
	if flip_curve:
		_curve_sign *= -1.0
	if _segment_len > 1.0:
		_velocity = (_segment_end - _segment_start).normalized() * _speed
	else:
		_velocity = Vector2.ZERO


func _advance_segment(dt: float) -> bool:
	if _segment_len <= 1.0:
		global_position = _segment_end
		_velocity = Vector2.ZERO
		return true

	var remaining: float = global_position.distance_to(_segment_end)
	if remaining <= 10.0:
		global_position = _segment_end
		_velocity = Vector2.ZERO
		return true

	var prev_pos: Vector2 = global_position
	var t_raw: float = 0.0
	if _is_linear_decel_mode:
		# 100px 内直线运动逻辑保持不变（指数递减推进）
		var remaining_ratio: float = clamp(remaining / _segment_len, 0.0, 1.0)
		var speed_scale: float = exp(-_accel_exponent * (1.0 - remaining_ratio))
		var raw_speed: float = _linear_decel_speed * speed_scale
		var cur_speed: float = raw_speed if raw_speed >= 1.0 else 0.0
		if cur_speed <= 0.0:
			_velocity = Vector2.ZERO
			return false
		var delta_progress: float = (cur_speed * dt) / _segment_len
		_segment_progress = min(_segment_progress + delta_progress, 1.0)
		t_raw = _segment_progress
	else:
		# 抛物线段使用固定总时长位移曲线：前快后慢，且在有限时间内精确到达终点
		_segment_elapsed_sec = min(_segment_elapsed_sec + dt, _segment_duration_sec)
		var time_ratio: float = 1.0 if _segment_duration_sec <= 0.0001 else _segment_elapsed_sec / _segment_duration_sec
		t_raw = _eval_curve_displacement_ratio(time_ratio)
		_segment_progress = t_raw

	var base_pos: Vector2 = _segment_start.lerp(_segment_end, t_raw)
	var dir: Vector2 = (_segment_end - _segment_start).normalized()
	var normal: Vector2 = Vector2(-dir.y, dir.x)
	var wave: float = 0.0
	if _curve_amplitude > 0.0 and _curve_cycles > 0.0 and _segment_wave_scale > 0.0:
		wave = sin(t_raw * TAU * _curve_cycles) * _segment_curve_amplitude * _segment_wave_scale * _curve_sign

	global_position = base_pos + normal * wave
	_velocity = (global_position - prev_pos) / max(dt, 0.0001)

	if _segment_progress >= 1.0:
		global_position = _segment_end
		return true
	return false


func _eval_curve_displacement_ratio(time_ratio: float) -> float:
	var t: float = clamp(time_ratio, 0.0, 1.0)
	if t <= CURVE_FAST_PHASE_TIME_RATIO:
		return t * (CURVE_FAST_PHASE_DISPLACEMENT_RATIO / CURVE_FAST_PHASE_TIME_RATIO)

	var slow_t: float = (t - CURVE_FAST_PHASE_TIME_RATIO) / max(1.0 - CURVE_FAST_PHASE_TIME_RATIO, 0.0001)
	var eased: float = 1.0 - pow(1.0 - slow_t, 2.0)
	return lerp(CURVE_FAST_PHASE_DISPLACEMENT_RATIO, 1.0, eased)


func _get_return_position() -> Vector2:
	if _owner_snake != null and is_instance_valid(_owner_snake):
		if _owner_snake.has_method("get_eye_socket_position"):
			return _owner_snake.call("get_eye_socket_position") as Vector2
		return _owner_snake.global_position
	return global_position


func _on_returned() -> void:
	if _owner_snake != null and is_instance_valid(_owner_snake):
		if _owner_snake.has_method("on_eye_projectile_returned"):
			_owner_snake.call("on_eye_projectile_returned")
	_destroy_self()


func _on_body_entered(body: Node) -> void:
	if _done:
		return
	if body == _owner_snake:
		return

	# 命中玩家 → 石化
	if body.is_in_group("player"):
		if body.has_method("apply_petrify"):
			body.call("apply_petrify")
		# 命中后开始返航（不销毁，继续飞回）
		if _phase == Phase.OUTBOUND or _phase == Phase.RETARGET or _phase == Phase.HOVER:
			_start_return()


func _destroy_self() -> void:
	if _done:
		return
	_done = true
	if _owner_snake != null and is_instance_valid(_owner_snake):
		if _owner_snake.has_method("on_eye_projectile_destroyed"):
			_owner_snake.call("on_eye_projectile_destroyed")
	queue_free()
