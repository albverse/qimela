extends ChimeraBase
class_name ChimeraStoneSnake

# ===== 攻击参数（Inspector可调）=====
@export var attack_range: float = 200.0
# 攻击范围（检测玩家距离）

@export var attack_cooldown: float = 1.0
# 攻击间隔（秒）

@export var bullet_speed: float = 400.0
# 子弹速度

@export var bullet_stun_time: float = 0.5
# 玩家被击中后僵直时间

@export var bullet_texture_path: String = "res://hp_sprite.png"
# 子弹贴图路径

@export var detection_area_path: NodePath = ^"DetectionArea"
# 检测区域节点路径

# ===== 运行时状态 =====
var _attack_timer: float = 0.0
var _player_in_range: bool = false
var _target_player: Player = null
var _bullet_texture: Texture2D = null

@onready var _detection_area: Area2D = get_node_or_null(detection_area_path) as Area2D

func _ready() -> void:
	# 设置物种ID
	species_id = &"chimera_stone_snake"
	
	# 设置属性：中型，无属性
	attribute_type = AttributeType.NORMAL
	size_tier = SizeTier.MEDIUM
	
	# 奇美拉特有属性：无法被链接
	follow_player_when_linked = false  # 不跟随
	can_be_attacked = false            # 无法被攻击
	is_flying = false                  # 陆行
	
	# 加载子弹贴图
	if ResourceLoader.exists(bullet_texture_path):
		_bullet_texture = load(bullet_texture_path) as Texture2D
	
	# 设置检测区域
	if _detection_area != null:
		_detection_area.body_entered.connect(_on_body_entered)
		_detection_area.body_exited.connect(_on_body_exited)
	
	super._ready()

func _physics_process(dt: float) -> void:
	super._physics_process(dt)
	
	# 攻击逻辑
	if _player_in_range and _target_player != null and is_instance_valid(_target_player):
		_attack_timer -= dt
		if _attack_timer <= 0.0:
			_fire_bullet()
			_attack_timer = attack_cooldown

# ===== 重写：无法被锁链链接 =====
func on_chain_hit(_player_ref: Node, _slot: int) -> int:
	# 返回0表示无法链接
	return 0

# ===== 检测区域回调 =====
func _on_body_entered(body: Node2D) -> void:
	if body is Player:
		_player_in_range = true
		_target_player = body as Player
		_attack_timer = 0.0  # 立即开始攻击

func _on_body_exited(body: Node2D) -> void:
	if body is Player:
		_player_in_range = false
		if _target_player == body:
			_target_player = null

# ===== 发射子弹 =====
func _fire_bullet() -> void:
	if _target_player == null or not is_instance_valid(_target_player):
		return
	
	# 创建子弹
	var bullet: Node2D = _create_bullet()
	if bullet == null:
		return
	
	# 设置位置和方向
	bullet.global_position = global_position
	var dir: Vector2 = (_target_player.global_position - global_position).normalized()
	
	# 添加到场景
	get_parent().add_child(bullet)
	
	# 设置子弹速度
	if bullet.has_method("set_velocity"):
		bullet.call("set_velocity", dir * bullet_speed)
	elif bullet.get("velocity") != null:
		bullet.set("velocity", dir * bullet_speed)
	
	# 设置子弹参数
	if bullet.has_method("set_stun_time"):
		bullet.call("set_stun_time", bullet_stun_time)

func _create_bullet() -> Node2D:
	# 动态创建子弹节点
	var bullet := Area2D.new()
	bullet.name = "StoneSnakeBullet"
	
	# 添加Sprite
	var sprite := Sprite2D.new()
	sprite.texture = _bullet_texture
	sprite.scale = Vector2(0.3, 0.3)  # 缩小子弹
	bullet.add_child(sprite)
	
	# 添加碰撞形状
	var collision := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 10.0
	collision.shape = shape
	bullet.add_child(collision)
	
	# 设置碰撞层（只与玩家碰撞）
	bullet.collision_layer = 0
	bullet.collision_mask = 2  # PlayerBody layer
	
	# 添加子弹脚本
	var script := GDScript.new()
	script.source_code = _get_bullet_script()
	script.reload()
	bullet.set_script(script)
	
	# 初始化子弹参数
	bullet.set("stun_time", bullet_stun_time)
	bullet.set("speed", bullet_speed)
	
	return bullet

func _get_bullet_script() -> String:
	return """extends Area2D

var velocity: Vector2 = Vector2.ZERO
var speed: float = 400.0
var stun_time: float = 0.5
var lifetime: float = 3.0
var _timer: float = 0.0

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _physics_process(dt: float) -> void:
	global_position += velocity * dt
	_timer += dt
	if _timer >= lifetime:
		queue_free()

func _on_body_entered(body: Node) -> void:
	if body is Player:
		var p: Player = body as Player
		if p.has_method("apply_stun"):
			p.call("apply_stun", stun_time)
		elif p.has_method("apply_damage"):
			# 如果没有apply_stun，尝试用伤害代替
			p.call("apply_damage", 1, global_position)
		queue_free()

func set_velocity(v: Vector2) -> void:
	velocity = v

func set_stun_time(t: float) -> void:
	stun_time = t
"""
