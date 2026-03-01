extends Area2D
class_name StoneMaskBirdFaceBullet

@export var speed: float = 720.0
@export var life_sec: float = 3.0
var _homing_duration_sec: float = 0.0
var _target: Node2D = null

var _velocity: Vector2 = Vector2.ZERO
var _alive_sec: float = 0.0


func setup(dir: Vector2, bullet_speed: float, target: Node2D, homing_duration_sec: float = 2.0) -> void:
	_velocity = dir.normalized() * max(1.0, bullet_speed)
	speed = bullet_speed
	_target = target
	_homing_duration_sec = max(0.0, homing_duration_sec)


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _physics_process(dt: float) -> void:
	if _alive_sec < _homing_duration_sec and _target != null and is_instance_valid(_target):
		var to_target := _target.global_position - global_position
		if to_target != Vector2.ZERO:
			_velocity = to_target.normalized() * max(1.0, speed)
	global_position += _velocity * dt
	_alive_sec += dt
	if _alive_sec >= life_sec:
		queue_free()


func _on_body_entered(body: Node) -> void:
	if body == null:
		return
	if body.is_in_group("player"):
		if body.has_method("apply_hit"):
			var hit := HitData.create(1, null, &"stone_mask_face_bullet")
			body.call("apply_hit", hit)
		queue_free()
