extends MonsterBase
class_name MonsterHostile

# =============================================================================
# MonsterHostile - 敌对怪物（融合失败产物）
# 特点：无法进入虚弱状态，被杀死后掉落治愈精灵
# =============================================================================

@export var move_speed: float = 100.0  # 移动速度(像素/秒) - 比普通怪快
@export var gravity: float = 1200.0  # 重力加速度
@export var healing_drop_count: int = 2  # 死亡时掉落的治愈精灵数量

var _dir: int = 1  # 移动方向

func _ready() -> void:
	# ===== 物种设置 =====
	species_id = &"hostile_fail"  # 物种ID
	attribute_type = AttributeType.NORMAL  # 属性：无
	size_tier = SizeTier.MEDIUM  # 型号：中型
	entity_type = EntityType.MONSTER  # 类型：怪物
	
	# ===== HP设置 =====
	max_hp = 5  # 最大HP
	weak_hp = 0  # 无法进入虚弱（关键！）
	has_hp = true
	
	# ===== 融合失败设置 =====
	fusion_fail_type = FailType.HOSTILE  # 再次融合失败也生成敌对怪
	
	super._ready()
	
	# 添加到特殊组
	add_to_group("hostile_monster")

func _do_move(dt: float) -> void:
	# 敌对怪物永远不会虚弱，所以不需要检查weak
	velocity.y += gravity * dt
	velocity.x = float(_dir) * move_speed
	move_and_slide()

	if is_on_wall():
		_dir *= -1

func _on_death() -> void:
	# 死亡时生成治愈精灵
	_spawn_healing_sprites()
	queue_free()

func _spawn_healing_sprites() -> void:
	var healing_scene: PackedScene = load("res://scene/HealingSprite.tscn") as PackedScene
	if healing_scene == null:
		return
	
	var parent: Node = get_parent()
	if parent == null:
		return
	
	for i in range(healing_drop_count):
		var h: Node = healing_scene.instantiate()
		if h is Node2D:
			var offset := Vector2(randf_range(-40, 40), randf_range(-20, 0))
			(h as Node2D).global_position = global_position + offset
		parent.add_child(h)
	
	print("[MonsterHostile] 死亡，生成 %d 只治愈精灵" % healing_drop_count)
