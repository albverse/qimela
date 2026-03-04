extends CharacterBody2D
class_name StoneMaskBirdFaceBullet

## 伤害值（命中玩家或怪物时扣除的 HP）
@export var damage: int = 1

## 飞行速度（px/s）
@export var speed: float = 720.0

## 存在时间（s）；超过后自动销毁
@export var life_sec: float = 10.0

## 追踪持续时间（s）；在此时间内持续转向目标；超过后变直线弹
@export var homing_duration_sec: float = 2.5

var _alive_sec: float = 0.0
var _bounce_count: int = 0
var _target: Node2D = null
var _reflected: bool = false
var _done: bool = false  # 防止同帧多次命中


func setup(dir: Vector2, bullet_speed: float, target: Node2D = null) -> void:
	velocity = dir.normalized() * max(1.0, bullet_speed)
	speed = bullet_speed
	_target = target


func _ready() -> void:
	# 物理层设置：
	#   collision_layer = 32（hazards/Layer6）
	#     → ghost_fist 的 hitbox（mask=40含32）可通过 area_entered 检测 BulletHurtbox 子节点
	#   collision_mask  = 7（World=1 + PlayerBody=2 + EnemyBody=4）
	#     → move_and_slide() 与地形/玩家/怪物发生物理碰撞，触发 _on_collide
	collision_layer = 32  # hazards(Layer6)
	collision_mask = 1 | 2 | 4  # World(1) + PlayerBody(2) + EnemyBody(4)

	# BulletHurtbox：Area2D 子节点，同置于 hazards(32) 层
	# ghost_fist 的 Area2D hitbox（mask=40）通过 area_entered 检测此节点，
	# _resolve_bullet() 从此节点向上走到 StoneMaskBirdFaceBullet，触发 reflect()
	var hb := Area2D.new()
	hb.name = "BulletHurtbox"
	hb.collision_layer = 32  # hazards(Layer6) = 1 << 5
	hb.collision_mask = 0
	var cs := CollisionShape2D.new()
	var sh := CircleShape2D.new()
	sh.radius = 8.0
	cs.shape = sh
	hb.add_child(cs)
	add_child(hb)


func _physics_process(dt: float) -> void:
	if _done:
		return

	# 追踪：反弹后取消，homing_duration_sec 内朝目标持续转向
	if not _reflected and _alive_sec < homing_duration_sec \
			and _target != null and is_instance_valid(_target):
		var desired_dir := (_target.global_position - global_position).normalized()
		if desired_dir != Vector2.ZERO:
			velocity = desired_dir * max(1.0, speed)

	rotation = 0.0
	move_and_slide()
	_alive_sec += dt

	if _alive_sec >= life_sec:
		queue_free()
		return

	# 碰撞处理（取第一个有效碰撞）
	for i: int in get_slide_collision_count():
		var col := get_slide_collision(i)
		if col == null:
			continue
		_on_collide(col)
		break


func _on_collide(collision: KinematicCollision2D) -> void:
	if collision == null or _done:
		return

	var collider := collision.get_collider()
	if collider == null or collider == self:
		return

	# 命中任意非自身目标：若可受击则造成伤害并销毁
	if collider.has_method("apply_hit"):
		_done = true
		var hit := HitData.create(damage, null, &"stone_mask_bird_face_bullet")
		collider.call("apply_hit", hit)
		queue_free()
		return

	# 与世界（及不可受击对象）碰撞：反弹，最多 3 次
	var n := collision.get_normal()
	if n != Vector2.ZERO:
		velocity = velocity.bounce(n)
	else:
		velocity = -velocity
	_reflected = true
	_target = null
	_bounce_count += 1
	if _bounce_count > 3:
		_done = true
		queue_free()


func reflect() -> void:
	## 被武器（ghost_fist / chimera_ghost_hand_l）反弹：
	## Y 轴速度翻转，取消追踪变直线弹
	_reflected = true
	_target = null
	velocity = Vector2(velocity.x, -velocity.y)
