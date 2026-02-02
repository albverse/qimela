extends MonsterBase
class_name MonsterHand

# =============================================================================
# 怪手 - 光属性怪物
# 注释
# =============================================================================

@export var move_speed: float = 100.0  # 移动速度(像素/秒) - 比普通飞怪快
@export var float_amp: float = 15.0  # 浮动幅度
@export var float_freq: float = 2.0  # 浮动频率

var _base_y: float = 0.0
var _t: float = 0.0
var _dir: int = 1

func _ready() -> void:
	# ===== 物种设置 =====
	species_id = &"hand_light"
	attribute_type = AttributeType.LIGHT  # 属性：光
	size_tier = SizeTier.SMALL  # 型号：小型
	entity_type = EntityType.MONSTER  # 类型：怪物
	
	# ===== HP设置 =====
	max_hp = 3  # 最大HP
	weak_hp = 1  # HP≤1时进入虚弱
	# ===== 泯灭融合次数 =====
	vanish_fusion_required = 1  # 虚弱后需要1次泯灭融合才会死亡
	
	super._ready()
	
	_base_y = global_position.y

func _do_move(dt: float) -> void:
	# 虚弱时停止移动
	if weak:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	# 正常移动（浮空左右飘）
	_t += dt
	velocity.x = float(_dir) * move_speed
	velocity.y = 0.0
	move_and_slide()

	# 碰墙转向
	if is_on_wall():
		_dir *= -1

	# 上下浮动
	global_position.y = _base_y + sin(_t * TAU * float_freq) * float_amp
