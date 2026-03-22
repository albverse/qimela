extends Area2D
class_name SoulCleaver

## =============================================================================
## SoulCleaver — 斩魂刀（地面弹幕，可被噬魂犬捡起）
## =============================================================================
## 组：soul_cleaver（噬魂犬通过 get_nodes_in_group 查询，不走 DetectArea）
## 生命周期：12 秒无人拾取后 queue_free
## claimed = true 时被一只犬锁定，不可被其他犬拾取（原 owner 优先）
## =============================================================================

## 锁定状态：同一时刻只能被一只犬锁定
var claimed: bool = false

## 掉刀者的 instance_id（用于原 owner 优先拾取逻辑）
var owner_instance_id: int = 0

## 可选初速度（throw_cleaver 事件时赋值）
var velocity: Vector2 = Vector2.ZERO

## 抛出衰减（每秒减速）
@export var friction: float = 400.0

## 最大存活时间（秒）
@export var life_time: float = 12.0

var _age: float = 0.0
var _moving: bool = false


func _ready() -> void:
	add_to_group("soul_cleaver")
	# SoulCleaver 仅需被噬魂犬检测到（组查询），不需要额外碰撞层
	collision_layer = 0
	collision_mask = 0
	monitorable = false
	monitoring = false

	if velocity != Vector2.ZERO:
		_moving = true


func _physics_process(dt: float) -> void:
	_age += dt
	if _age >= life_time:
		queue_free()
		return

	if _moving and velocity != Vector2.ZERO:
		# 简单摩擦减速
		var speed: float = velocity.length()
		speed = max(speed - friction * dt, 0.0)
		if speed <= 0.0:
			velocity = Vector2.ZERO
			_moving = false
		else:
			velocity = velocity.normalized() * speed
		global_position += velocity * dt
