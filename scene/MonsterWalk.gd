extends MonsterBase
class_name MonsterWalk

@export var move_speed: float = 70.0
@export var gravity: float = 1200.0

var _dir: int = -1

func _ready() -> void:
	max_hp = 5
	super._ready()

func _do_move(dt: float) -> void:
	if weak:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	velocity.y += gravity * dt
	velocity.x = float(_dir) * move_speed
	move_and_slide()

	if is_on_wall():
		_dir *= -1
