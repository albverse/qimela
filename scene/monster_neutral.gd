extends MonsterBase
class_name MonsterNeutral

# =============================================================================
# MonsterNeutral - 无属性怪物
# 可与任何属性融合，不会触发光暗冲突
# =============================================================================

@export var move_speed: float = 50.0  # 移动速度(像素/秒)
@export var gravity: float = 1200.0  # 重力加速度

var _dir: int = 1  # 移动方向

func _ready() -> void:
	# ===== 物种设置 =====
	species_id = &"neutral_small"  # 物种ID
	attribute_type = AttributeType.NORMAL  # 属性：无
	size_tier = SizeTier.SMALL  # 型号：小型
	# entity_type 已由 MonsterBase._ready() 统一设置

	# ===== HP设置 =====
	max_hp = 3  # 最大HP
	weak_hp = 1  # HP≤1时进入虚弱
	
	# ===== 泯灭融合次数 =====
	vanish_fusion_required = 1  # 虚弱后需要1次泯灭融合才会死亡
	
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
