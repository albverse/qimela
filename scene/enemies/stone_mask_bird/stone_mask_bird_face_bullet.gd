extends Area2D
class_name StoneMaskBirdFaceBullet

@export var speed: float = 720.0
@export var life_sec: float = 3.0

var _velocity: Vector2 = Vector2.ZERO
var _alive_sec: float = 0.0


func setup(dir: Vector2, bullet_speed: float) -> void:
	_velocity = dir.normalized() * max(1.0, bullet_speed)
	speed = bullet_speed


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _physics_process(dt: float) -> void:
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
