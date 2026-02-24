extends EntityBase
class_name ChimeraBase

# ===== 奇美拉来源类型 =====
enum ChimeraOriginType {
	MONSTER_MONSTER = 1,
	CHIMERA_MONSTER = 2,
	CHIMERA_CHIMERA = 3,
	PRIMORDIAL = 4
}

# ===== 奇美拉专属属性 =====
@export var origin_type: ChimeraOriginType = ChimeraOriginType.MONSTER_MONSTER
@export var can_be_attacked: bool = false
@export var follow_player_when_linked: bool = true
@export var move_speed: float = 170.0
@export var is_flying: bool = false
@export var gravity: float = 1500.0
@export var accel: float = 1400.0
@export var stop_threshold_x: float = 6.0
@export var x_offset: float = 0.0

# 第3类：存储合成来源
var source_scenes: Array[PackedScene] = []

# 跟随/漫游
var _player: Node2D = null
var _wander_dir: int = 0
var _wander_t: float = 0.0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

func _ready() -> void:
	super._ready()
	entity_type = EntityType.CHIMERA
	has_hp = can_be_attacked
	add_to_group("chimera")
	_rng.randomize()
	_pick_next_wander()

func _physics_process(dt: float) -> void:
	if is_linked() and follow_player_when_linked and _player != null and is_instance_valid(_player):
		_move_toward_player(dt)
	else:
		_idle_behavior(dt)
	move_and_slide()

func _move_toward_player(dt: float) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	
	if is_flying:
		var target: Vector2 = _player.global_position
		var dir: Vector2 = (target - global_position)
		if dir.length() > stop_threshold_x:
			dir = dir.normalized()
			velocity = velocity.move_toward(dir * move_speed, accel * dt)
		else:
			velocity = velocity.move_toward(Vector2.ZERO, accel * dt)
	else:
		velocity.y += gravity * dt
		var target_x: float = _player.global_position.x + x_offset
		var dx: float = target_x - global_position.x
		if absf(dx) <= stop_threshold_x:
			velocity.x = move_toward(velocity.x, 0.0, accel * dt)
		else:
			var dir: float = signf(dx)
			velocity.x = move_toward(velocity.x, dir * move_speed, accel * dt)

func _idle_behavior(dt: float) -> void:
	if not is_flying:
		velocity.y += gravity * dt
	else:
		velocity.y = 0.0  # B9修复：飞行奇美拉 idle 时清零 Y 速度，防止跟随跳跃后残留
	_wander_t -= dt
	if _wander_t <= 0.0:
		_pick_next_wander()
	var desired := float(_wander_dir) * move_speed * 0.5
	velocity.x = move_toward(velocity.x, desired, accel * dt)

func _pick_next_wander() -> void:
	_wander_dir = _rng.randi_range(-1, 1)
	_wander_t = _rng.randf_range(1.0, 4.0)

func on_chain_hit(_player_ref: Node, slot: int) -> int:
	if is_occupied_by_other_chain(slot):
		return 0
	_linked_player = _player_ref
	_player = _player_ref as Node2D
	# 不在这里调用on_chain_attached，让player_chain_system统一调用
	return 1

# ========== 修复问题2：确保再次链接时_player被正确设置 ==========
func on_chain_attached(slot: int) -> void:
	super.on_chain_attached(slot)
	
	# 关键修复：如果_player为null，从_linked_player获取或从player组获取
	if _player == null:
		if _linked_player != null and is_instance_valid(_linked_player):
			_player = _linked_player as Node2D
		else:
			# 从player组获取
			var players: Array = get_tree().get_nodes_in_group("player")
			if not players.is_empty():
				_player = players[0] as Node2D
				_linked_player = _player

func on_chain_detached(slot: int) -> void:
	var was_linked: bool = is_linked() and get_linked_slot() == slot
	super.on_chain_detached(slot)
	
	# 只有真正断开链接时才清空_player
	if was_linked and not is_linked():
		_player = null
		if origin_type == ChimeraOriginType.CHIMERA_CHIMERA:
			_decompose()

func _decompose() -> void:
	if source_scenes.is_empty():
		return
	var count := source_scenes.size()
	var positions := _calculate_decompose_positions(count)
	for i in range(count):
		var scene: PackedScene = source_scenes[i]
		if scene == null:
			continue
		var entity: Node = scene.instantiate()
		if entity is Node2D:
			(entity as Node2D).global_position = positions[i]
		get_parent().add_child(entity)
	queue_free()

func _calculate_decompose_positions(count: int) -> Array[Vector2]:
	var positions: Array[Vector2] = []
	var base: Vector2 = global_position
	if _player != null and is_instance_valid(_player):
		base = _player.global_position
	
	if count == 2:
		var left := base + Vector2(-80, 0)
		var right := base + Vector2(80, 0)
		if not _is_position_blocked(left):
			positions.append(left)
		else:
			positions.append(base + Vector2(-40, -50))
		if not _is_position_blocked(right):
			positions.append(right)
		else:
			positions.append(base + Vector2(40, -50))
	else:
		for i in range(count):
			var angle: float = TAU * float(i) / float(count)
			var offset := Vector2(cos(angle), sin(angle)) * 80.0
			positions.append(base + offset)
	return positions

func _is_position_blocked(_pos: Vector2) -> bool:
	# TODO: 物理检测
	return false

func setup(p: Node2D) -> void:
	set_player(p)

func set_player(p: Node2D) -> void:
	_player = p

# ===== 互动效果（子类重写）=====
func on_player_interact(_player_ref: Player) -> void:
	pass

# set_fusion_vanish 已统一在 EntityBase 中实现，此处不再重复
