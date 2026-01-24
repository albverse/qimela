extends MonsterBase
class_name MonsterFly

@export var move_speed: float = 90.0
@export var float_amp: float = 12.0
@export var float_freq: float = 2.4

var _base_y: float = 0.0
var _t: float = 0.0
var _dir: int = 1


func _ready() -> void:
	add_to_group("flying_monster")
	# 你原来的 _ready 逻辑继续放下面
	max_hp = 3
	super._ready()
	_base_y = global_position.y

func _do_move(dt: float) -> void:
	if weak:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	_t += dt
	velocity.x = float(_dir) * move_speed
	velocity.y = 0.0
	move_and_slide()

	# 简单来回飞
	if is_on_wall():
		_dir *= -1

	# 漂浮
	global_position.y = _base_y + sin(_t * TAU * float_freq) * float_amp
