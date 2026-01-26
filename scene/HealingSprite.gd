extends Node2D
class_name HealingSprite

enum State { IDLE_IN_WORLD, ACQUIRE, ORBIT, CONSUMED }

# 吸附参数
@export var acquire_range: float = 150.0
@export var acquire_delay: float = 1.0
@export var acquire_accel: float = 800.0
@export var acquire_max_speed: float = 300.0

# 环绕参数
@export var orbit_radius_x: float = 60.0
@export var orbit_radius_y: float = 40.0  # 椭圆，y轴压扁
@export var orbit_speed: float = 2.0
@export var scale_min: float = 0.7
@export var scale_max: float = 1.0

# 视觉节点（为Spine替换预留）
@export var visual_path: NodePath = ^"Sprite2D"

var state: State = State.IDLE_IN_WORLD
var player: Player = null
var orbit_index: int = 0  # 0或1
var orbit_angle: float = 0.0
var velocity: Vector2 = Vector2.ZERO
var acquire_timer: float = 0.0

@onready var visual: Node2D = get_node_or_null(visual_path)

func _ready() -> void:
	add_to_group("healing_sprite")
	if state == State.IDLE_IN_WORLD:
		_check_player_nearby()

func _physics_process(dt: float) -> void:
	match state:
		State.IDLE_IN_WORLD:
			_check_player_nearby()
		State.ACQUIRE:
			_update_acquire(dt)
		State.ORBIT:
			_update_orbit(dt)

func _check_player_nearby() -> void:
	if player != null:
		return
	
	var p = get_tree().get_first_node_in_group("player") as Player
	if p == null:
		return
	
	var dist = global_position.distance_to(p.global_position)
	if dist < acquire_range:
		print("[HealingSprite] 玩家靠近，开始吸附")  # 添加日志
		_start_acquire(p)

func _start_acquire(p: Player) -> void:
	player = p
	state = State.ACQUIRE
	acquire_timer = 0.0
	velocity = Vector2.ZERO
	
	if player.has_method("try_collect_healing_sprite"):
		orbit_index = player.call("try_collect_healing_sprite", self)
		if orbit_index < 0:
			queue_free()  # 已满
			return

func _update_acquire(dt: float) -> void:
	if player == null or not is_instance_valid(player):
		state = State.IDLE_IN_WORLD
		player = null
		return
	
	acquire_timer += dt
	
	# 延迟后开始加速
	if acquire_timer < acquire_delay:
		return
	
	var dir = (player.global_position - global_position).normalized()
	velocity += dir * acquire_accel * dt
	if velocity.length() > acquire_max_speed:
		velocity = velocity.normalized() * acquire_max_speed
	
	global_position += velocity * dt
	
	# 到达玩家附近，切换环绕
	if global_position.distance_to(player.global_position) < 30.0:
		_start_orbit()

func _start_orbit() -> void:
	state = State.ORBIT
	orbit_angle = float(orbit_index) * PI  # 相位错开180度
	velocity = Vector2.ZERO

func _update_orbit(dt: float) -> void:
	if player == null or not is_instance_valid(player):
		queue_free()
		return
	
	orbit_angle += orbit_speed * dt
	
	# 椭圆轨道
	var offset_x = cos(orbit_angle) * orbit_radius_x
	var offset_y = sin(orbit_angle) * orbit_radius_y
	
	global_position = player.global_position + Vector2(offset_x, offset_y)
	
	# 伪3D：scale + z_index
	var depth = sin(orbit_angle)  # -1到1
	var t = (depth + 1.0) / 2.0  # 0到1
	
	if visual:
		visual.scale = Vector2.ONE * lerp(scale_min, scale_max, t)
	
	z_index = 1 if depth > 0 else -1

# 锁链击中触发
func on_chain_hit(_player: Node, _slot: int) -> int:
	if state == State.IDLE_IN_WORLD:
		_start_acquire(_player as Player)
		return 0
	return 0

# 消耗
func consume() -> void:
	state = State.CONSUMED
	queue_free()
