extends Area2D
class_name StoneMaskBirdFaceBullet

@export var speed: float = 720.0
@export var life_sec: float = 3.0
@export var spin_deg_per_sec: float = 360.0

var _velocity: Vector2 = Vector2.ZERO
var _alive_sec: float = 0.0
var _visual: Node2D = null


func setup(dir: Vector2, bullet_speed: float, bullet_spin_deg_per_sec: float = spin_deg_per_sec) -> void:
	_velocity = dir.normalized() * max(1.0, bullet_speed)
	speed = bullet_speed
	spin_deg_per_sec = bullet_spin_deg_per_sec


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	for child in get_children():
		if child is Node2D:
			_visual = child
			break


func _physics_process(dt: float) -> void:
	global_position += _velocity * dt
	if _visual != null:
		_visual.rotation += deg_to_rad(spin_deg_per_sec) * dt
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
