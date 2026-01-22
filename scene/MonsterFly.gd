extends MonsterBase
class_name MonsterFly

# ===== 飞行怪：简单悬浮（方块素材也能看出状态）=====
@export var hover_amp: float = 10.0      # 上下浮动幅度
@export var hover_freq: float = 3.0      # 浮动频率
@export var drift_speed: float = 60.0    # 横向漂移（可为 0）
@export var drift_dir: float = 1.0       # 1 或 -1

var _t: float = 0.0
var _base_y: float = 0.0

func _ready() -> void:
	super._ready()
	_base_y = global_position.y

func _physics_process(dt: float) -> void:
	super._physics_process(dt)

	if weak:
		# 昏迷：原地停住
		velocity = Vector2.ZERO
		move_and_slide()
		return

	if is_stunned():
		# 僵直：暂停漂移/浮动（视觉更明确）
		velocity = Vector2.ZERO
		move_and_slide()
		return

	_t += dt
	var y := _base_y + sin(_t * TAU * hover_freq) * hover_amp
	var dy := y - global_position.y

	velocity.x = drift_speed * drift_dir
	velocity.y = dy / max(dt, 0.0001)

	move_and_slide()
