extends MonsterBase
class_name MonsterWalkB

# =============================================================================
# MonsterWalkB - 第二种暗属性走怪（紫色）
# 用于测试：暗+暗 = FAIL_HOSTILE
# =============================================================================

@export var move_speed: float = 80.0  # 移动速度(像素/秒) - 比普通走怪快
@export var gravity: float = 1200.0  # 重力加速度

var _dir: int = -1  # 移动方向

func _ready() -> void:
	# ===== 物种设置 =====
	species_id = &"walk_dark_b"  # 物种ID（不同于walk_dark）
	attribute_type = AttributeType.DARK  # 属性：暗
	size_tier = SizeTier.SMALL  # 型号：小型
	# entity_type 已由 MonsterBase._ready() 统一设置

	# ===== HP设置 =====
	max_hp = 4  # 最大HP
	weak_hp = 1  # HP≤1时进入虚弱
	
	# ===== 泯灭融合次数 =====
	vanish_fusion_required = 1  # 虚弱后需要1次泯灭融合才会死亡
	
	super._ready()

func _do_move(dt: float) -> void:
	# 虚弱时停止移动
	if weak:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	# 正常移动
	velocity.y += gravity * dt
	velocity.x = float(_dir) * move_speed
	move_and_slide()

	# 碰墙转向
	if is_on_wall():
		_dir *= -1
