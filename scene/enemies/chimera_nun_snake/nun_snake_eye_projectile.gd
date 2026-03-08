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
var _speed: float = 420.0
var _hover_sec: float = 0.5
var _retarget_count: int = 3
var _return_speed: float = 700.0
var _max_lifetime_sec: float = 10.0

var _remaining_retargets: int = 0
var _hover_timer: float = 0.0
var _lifetime_timer: float = 0.0
var _target_pos: Vector2 = Vector2.ZERO
var _done: bool = false
var _velocity: Vector2 = Vector2.ZERO


func setup(
	target: Node2D,
	owner_snake: Node2D,
	speed: float,
	hover_sec: float,
	retarget_count: int,
	return_speed: float,
	max_lifetime_sec: float
) -> void:
	_target = target
	_owner_snake = owner_snake
	_speed = speed
	_hover_sec = hover_sec
	_retarget_count = retarget_count
	_remaining_retargets = retarget_count
	_return_speed = return_speed
	_max_lifetime_sec = max_lifetime_sec

	# 初始飞行方向
	if _target != null and is_instance_valid(_target):
		_target_pos = _target.global_position
		_velocity = (global_position.direction_to(_target_pos)) * _speed
	_phase = Phase.OUTBOUND


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
		Phase.HOVER:
			_process_hover(dt)
		Phase.RETURNING:
			_process_return(dt)
		Phase.FORCE_RECALL:
			_process_force_recall(dt)


func _process_fly(dt: float) -> void:
	# 飞向目标位置
	var dir: Vector2 = global_position.direction_to(_target_pos)
	_velocity = dir * _speed
	global_position += _velocity * dt

	# 到达目标附近
	if global_position.distance_to(_target_pos) <= 10.0:
		if _remaining_retargets > 0:
			_phase = Phase.HOVER
			_hover_timer = 0.0
			_velocity = Vector2.ZERO
		else:
			_start_return()


func _process_hover(dt: float) -> void:
	_hover_timer += dt
	if _hover_timer >= _hover_sec:
		# 重新锁定目标位置
		_remaining_retargets -= 1
		if _target != null and is_instance_valid(_target):
			_target_pos = _target.global_position
		_phase = Phase.RETARGET

		# 更新 owner 的 eye_phase
		if _owner_snake != null and is_instance_valid(_owner_snake):
			_owner_snake.eye_phase = ChimeraNunSnake.EyePhase.RETARGETING


func _start_return() -> void:
	_phase = Phase.RETURNING
	if _owner_snake != null and is_instance_valid(_owner_snake):
		_owner_snake.eye_phase = ChimeraNunSnake.EyePhase.RETURNING


func _process_return(dt: float) -> void:
	var return_pos: Vector2 = _get_return_position()
	var dir: Vector2 = global_position.direction_to(return_pos)
	global_position += dir * _return_speed * dt

	if global_position.distance_to(return_pos) <= 15.0:
		_on_returned()


func _process_force_recall(dt: float) -> void:
	var return_pos: Vector2 = _get_return_position()
	var dir: Vector2 = global_position.direction_to(return_pos)
	# 强制返航用更快速度
	global_position += dir * _return_speed * 1.5 * dt

	if global_position.distance_to(return_pos) <= 15.0:
		_on_returned()


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
