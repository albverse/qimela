extends Area2D
class_name GhostWraith

@export var speed: float = 140.0
@export var life_sec: float = 10.0
var _dir := Vector2.RIGHT

func _ready() -> void:
	add_to_group("ghost_wraith")
	body_entered.connect(_on_body_entered)

func setup(dir: Vector2) -> void:
	_dir = dir.normalized()

func _physics_process(dt: float) -> void:
	global_position += _dir * speed * dt
	life_sec -= dt
	if life_sec <= 0.0:
		queue_free()

func _on_body_entered(body: Node) -> void:
	if body and body.is_in_group("player") and body.has_method("apply_damage"):
		body.call("apply_damage", 1, global_position)
