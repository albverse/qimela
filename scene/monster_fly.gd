extends MonsterBase
class_name MonsterFly

# =============================================================================
# MonsterFly - 光属性飞行怪物（有显隐机制）
# =============================================================================

# ===== 移动参数 =====
@export var move_speed: float = 90.0  # 水平移动速度(像素/秒)
@export var float_amp: float = 12.0  # 上下浮动幅度(像素)
@export var float_freq: float = 2.4  # 上下浮动频率(Hz)

# ===== 可见性系统 =====
@export var visible_time: float = 0.0  # 当前可见时间(秒)
@export var visible_time_max: float = 6.0  # 最大可见时间(秒)
@export var opacity_full_threshold: float = 3.0  # 完全不透明的阈值(秒)
@export var fade_curve: Curve = null  # 淡入淡出曲线

var _base_y: float = 0.0  # 基准Y坐标
var _t: float = 0.0  # 时间累计
var _dir: int = 1  # 移动方向
var _is_visible: bool = false  # 当前是否可见

var _saved_body_layer: int = -1  # 保存的碰撞层
var _saved_body_mask: int = -1  # 保存的碰撞掩码

@export var light_node_path: NodePath = ^"PointLight2D"  # 光源节点路径
@onready var _point_light: PointLight2D = get_node_or_null(light_node_path) as PointLight2D

func _ready() -> void:
	add_to_group("flying_monster")
	
	# ===== 物种设置 =====
	species_id = &"fly_light"  # 物种ID
	attribute_type = AttributeType.LIGHT  # 属性：光
	size_tier = SizeTier.SMALL  # 型号：小型
	entity_type = EntityType.MONSTER  # 类型：怪物
	
	# ===== HP设置 =====
	max_hp = 3  # 最大HP
	weak_hp = 1  # HP≤1时进入虚弱
	
	# ===== 泯灭融合次数 =====
	vanish_fusion_required = 2  # 虚弱后需要2次泯灭融合才会死亡（比走怪更难杀）
	
	_saved_body_layer = collision_layer
	_saved_body_mask = collision_mask
	
	super._ready()
	
	_base_y = global_position.y
	
	if visible_time <= 0.0:
		_switch_to_invisible()
	else:
		_switch_to_visible()

func _physics_process(dt: float) -> void:
	_update_visibility(dt)
	super._physics_process(dt)

func _update_visibility(dt: float) -> void:
	if light_counter > 0.0:
		var transfer: float = min(light_counter, dt * 10.0)
		visible_time += transfer
		light_counter -= transfer
		visible_time = min(visible_time, visible_time_max)
	
	if visible_time > 0.0:
		if not _is_visible:
			_switch_to_visible()
		_update_opacity()
		visible_time -= dt
		visible_time = max(visible_time, 0.0)
	else:
		if _is_visible:
			_on_visibility_timeout()

func _update_opacity() -> void:
	if sprite == null:
		return
	var alpha: float
	if visible_time >= opacity_full_threshold:
		alpha = 1.0
	else:
		var t: float = visible_time / opacity_full_threshold
		if fade_curve != null:
			alpha = fade_curve.sample(t)
		else:
			alpha = lerpf(0.0, 1.0, t)
	sprite.modulate.a = alpha
	if _point_light:
		_point_light.energy = alpha * 1.0

func _switch_to_visible() -> void:
	_is_visible = true
	if _saved_body_layer != -1:
		collision_layer = _saved_body_layer
		collision_mask = _saved_body_mask
	if sprite:
		sprite.visible = true
		sprite.modulate.a = 1.0
	var hurtbox := get_node_or_null("Hurtbox") as Area2D
	if hurtbox:
		hurtbox.set_deferred("monitorable", true)
		hurtbox.set_deferred("monitoring", true)
		var hurtbox_shape := hurtbox.get_node_or_null("CollisionShape2D") as CollisionShape2D
		if hurtbox_shape:
			hurtbox_shape.disabled = false
	if _point_light:
		_point_light.enabled = true

func _switch_to_invisible() -> void:
	_is_visible = false
	collision_layer = 0
	if sprite:
		sprite.visible = false
		sprite.modulate.a = 0.0
	var hurtbox := get_node_or_null("Hurtbox") as Area2D
	if hurtbox:
		hurtbox.set_deferred("monitorable", false)
		hurtbox.set_deferred("monitoring", false)
		var hurtbox_shape := hurtbox.get_node_or_null("CollisionShape2D") as CollisionShape2D
		if hurtbox_shape:
			hurtbox_shape.disabled = true
	if _point_light:
		_point_light.enabled = false

func _on_visibility_timeout() -> void:
	_switch_to_invisible()
	_force_release_all_chains()

func is_visible_for_chain() -> bool:
	return _is_visible

func _force_release_all_chains() -> void:
	if _linked_slots.is_empty():
		return
	var slots: Array[int] = _linked_slots.duplicate()
	var p: Node = _linked_player
	_linked_slots.clear()
	_linked_player = null
	if p == null or not is_instance_valid(p):
		return

	var chain_target: Node = null
	if p.has_method("force_dissolve_chain"):
		chain_target = p
	elif "chain_sys" in p and p.chain_sys != null:
		chain_target = p.chain_sys
	elif p.has_node("Components/ChainSystem"):
		chain_target = p.get_node_or_null("Components/ChainSystem")

	if chain_target == null or not chain_target.has_method("force_dissolve_chain"):
		return

	for s in slots:
		chain_target.call("force_dissolve_chain", s)

func _do_move(dt: float) -> void:
	if weak:
		velocity = Vector2.ZERO
		move_and_slide()
		return
	_t += dt
	velocity.x = float(_dir) * move_speed
	velocity.y = 0.0
	move_and_slide()
	if is_on_wall():
		_dir *= -1
	global_position.y = _base_y + sin(_t * TAU * float_freq) * float_amp
