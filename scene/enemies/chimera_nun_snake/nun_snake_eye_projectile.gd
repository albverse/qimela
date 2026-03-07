extends Area2D
class_name NunSnakeEyeProjectile

## =============================================================================
## NunSnakeEyeProjectile - 修女蛇眼球子弹
## =============================================================================
## 独立实例场景，不走普通 projectile 伤害路由。
## 行为：飞向玩家 → 悬停 → 重定向（共 retarget_count 次）→ 返航 → 销毁。
## 强制召回：宿主进入 WEAK/STUN 时，eye_phase 切为 FORCE_RECALL，调用 force_recall()。
## 命中效果：玩家触碰 → 进入 PETRIFIED 状态。
## =============================================================================

enum Phase {
	OUTBOUND,    ## 飞向目标
	HOVER,       ## 悬停
	RETARGET,    ## 重新锁定目标
	RETURNING,   ## 返航
	FORCE_RECALL ## 强制召回（高速返航后销毁）
}

## ===== 运行时参数（由宿主 setup() 写入）=====
var _host: ChimeraNunSnake = null
var _speed: float = 420.0
var _hover_sec: float = 0.5
var _retarget_count: int = 3
var _return_speed: float = 700.0
var _max_lifetime_sec: float = 10.0

## ===== 内部状态 =====
var _phase: int = Phase.OUTBOUND
var _target_pos: Vector2 = Vector2.ZERO
var _hover_timer: float = 0.0
var _retarget_done: int = 0
var _lifetime_timer: float = 0.0
var _velocity: Vector2 = Vector2.ZERO


func setup(host: ChimeraNunSnake) -> void:
	_host = host
	_speed = host.eye_projectile_speed
	_hover_sec = host.eye_projectile_hover_sec
	_retarget_count = host.eye_projectile_retarget_count
	_return_speed = host.eye_return_speed
	_max_lifetime_sec = host.eye_projectile_max_lifetime_sec
	_retarget_done = 0
	_phase = Phase.OUTBOUND
	_lock_onto_player()


func _ready() -> void:
	# 眼球子弹不可被攻击命中，不参与普通地面刚体碰撞
	# collision_layer = 0：不在任何物理层上（不被其他 Area 感知）
	# collision_mask = 2：检测 PlayerBody（用于触发石化）
	collision_layer = 0   # 无层（不可被命中）
	collision_mask = 2    # PlayerBody(2)
	body_entered.connect(_on_body_entered)


func _physics_process(dt: float) -> void:
	_lifetime_timer += dt
	if _lifetime_timer >= _max_lifetime_sec:
		_cleanup()
		return

	match _phase:
		Phase.OUTBOUND:
			_tick_outbound(dt)
		Phase.HOVER:
			_tick_hover(dt)
		Phase.RETARGET:
			_tick_outbound(dt)  # 重定向阶段复用飞行逻辑
		Phase.RETURNING:
			_tick_returning(dt, _return_speed)
		Phase.FORCE_RECALL:
			_tick_returning(dt, _return_speed * 2.0)


func _tick_outbound(dt: float) -> void:
	var dir: Vector2 = (_target_pos - global_position)
	if dir.length() <= 10.0:
		# 到达目标位置
		_velocity = Vector2.ZERO
		_phase = Phase.HOVER
		_hover_timer = 0.0
		return
	_velocity = dir.normalized() * _speed
	global_position += _velocity * dt


func _tick_hover(dt: float) -> void:
	_hover_timer += dt
	if _hover_timer >= _hover_sec:
		if _retarget_done < _retarget_count:
			_retarget_done += 1
			_phase = Phase.RETARGET
			_lock_onto_player()
		else:
			# 完成所有重定向，开始返航
			_phase = Phase.RETURNING


func _tick_returning(dt: float, speed: float) -> void:
	if _host == null or not is_instance_valid(_host):
		_cleanup()
		return
	var return_pos: Vector2 = _host.get_eye_socket_world_pos()
	var dir: Vector2 = (return_pos - global_position)
	if dir.length() <= 12.0:
		# 到达眼窝
		if _phase == Phase.RETURNING:
			_host.notify_eye_returned()
		_cleanup()
		return
	_velocity = dir.normalized() * speed
	global_position += _velocity * dt


func _lock_onto_player() -> void:
	## 锁定当前玩家位置（快照，不跟踪）
	if _host == null:
		return
	var player: Node2D = _host.get_player()
	if player != null and is_instance_valid(player):
		_target_pos = player.global_position
	else:
		# 无玩家目标，直接返航
		_phase = Phase.RETURNING


func force_recall() -> void:
	## 宿主强制召回入口
	_phase = Phase.FORCE_RECALL


func _on_body_entered(body: Node) -> void:
	## 玩家触碰眼球 → 玩家进入 PETRIFIED 状态
	if body.is_in_group("player"):
		if body.has_method("enter_petrified"):
			body.call("enter_petrified")


func _cleanup() -> void:
	if is_inside_tree():
		queue_free()
