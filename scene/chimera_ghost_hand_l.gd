extends ChimeraBase
class_name ChimeraGhostHandL

## =============================================================================
## ChimeraGhostHandL - 幽灵手奇美拉·左（Beehave 行为树驱动）
## =============================================================================
## 由 石眼虫（空壳）+ 软体虫 融合产生。
## 被链接时跟随玩家操控移动（无重力）；攻击时冻结操控，出击结束后恢复。
## 受到伤害或超出链最大长度 → vanish → 回到玩家附近 → appear → idle。
## =============================================================================

# ===== 导出参数（策划可调）=====

@export var float_speed: float = 120.0
## 链接跟随速度（px/s）

@export var chain_overdist_threshold: float = 600.0
## 超出此距离时触发重置（px）

@export var attack_hitbox_radius: float = 40.0
## 攻击检测半径（px）

@export var attack_damage: int = 1
## 攻击伤害

@export var player_side_offset: float = 80.0
## 重置后贴近玩家的水平偏移（px）

@export var respawn_radius: float = 200.0
## 重置后围绕玩家选点的半径（px）

@export var respawn_up_offset: float = 100.0
## 重置后默认偏上高度（px）

@export var respawn_probe_side_step: float = 36.0
## 重置选点时左右探测步长（px）

@export var respawn_probe_up_step: float = 26.0
## 重置选点时向上探测步长（px）

@export var respawn_probe_tries: int = 6
## 重置选点时每侧最大探测层数

# ===== 内部状态（BT 叶节点读写）=====

## 是否受到了伤害 → 触发重置
var took_damage: bool = false

## 是否超出链距离 → 触发重置
var over_chain_limit: bool = false

## 断链后请求重置（vanish -> appear）
var detached_reset_pending: bool = false

## 攻击是否被请求（玩家输入层写入）
var attack_requested: bool = false

## 攻击期间冻结玩家操控输入
var control_input_frozen: bool = false

## 幽灵攻击命中检测窗口（hit_on/off 等效，供 ForceCloseHitWindows 使用）
var atk_hit_window_open: bool = false

## Spine 事件标志（_on_spine_event 置位，BT 叶节点读取后清零）
var ev_hit_on: bool = false
var ev_attack_done: bool = false

# ===== 动画状态追踪 =====

var _current_anim: StringName = &""
var _current_anim_finished: bool = false
var _current_anim_loop: bool = false

# ===== 动画驱动 =====

var _anim_driver: AnimDriverSpine = null
var _anim_mock: AnimDriverMock = null

@onready var _spine_sprite: Node = null
@onready var _attack_area: Area2D = get_node_or_null("AttackArea")

# ===== 生命周期 =====

func _ready() -> void:
	species_id = &"chimera_ghost_hand_l"
	attribute_type = AttributeType.NORMAL
	size_tier = SizeTier.MEDIUM
	is_flying = true
	# 禁用基类默认跟随：BT 的 Act_LinkedMove 负责位移
	follow_player_when_linked = false
	super._ready()
	add_to_group("chimera_ghost_hand_l")

	# AttackArea 检测 EnemyBody(3) + enemy_hurtbox(4) + hazards(6)，不含 PlayerBody 防止误伤玩家
	if _attack_area != null:
		_attack_area.collision_mask = 4 | 8 | 32  # EnemyBody(3) + enemy_hurtbox(4) + hazards(6)

	_spine_sprite = get_node_or_null("SpineSprite")
	if _spine_sprite and _spine_sprite.get_class() == "SpineSprite":
		_anim_driver = AnimDriverSpine.new()
		add_child(_anim_driver)
		_anim_driver.setup(_spine_sprite)
		_anim_driver.anim_completed.connect(_on_anim_completed)
		if _spine_sprite.has_signal("animation_event"):
			_spine_sprite.animation_event.connect(_on_spine_event)
	else:
		_anim_mock = AnimDriverMock.new()
		_setup_mock_durations()
		add_child(_anim_mock)
		_anim_mock.anim_completed.connect(_on_anim_completed)


func _physics_process(dt: float) -> void:
	# 链距超限检测
	if is_linked() and _player != null and is_instance_valid(_player):
		var dist := global_position.distance_to(_player.global_position)
		if dist > chain_overdist_threshold:
			over_chain_limit = true

	# Mock 驱动需要手动 tick
	if _anim_mock:
		_anim_mock.tick(dt)

	# 移动和 BT 逻辑由叶节点（+ BeehaveTree tick）驱动
	# 基类 _physics_process 不调用（is_flying=true，gravity 由 BT 管理）


# =============================================================================
# 动画接口（BT 叶节点统一调用）
# =============================================================================

func anim_play(anim_name: StringName, loop: bool, _interruptible: bool = true) -> void:
	if _current_anim == anim_name and not _current_anim_finished and _current_anim_loop == loop:
		return
	_current_anim = anim_name
	_current_anim_finished = false
	_current_anim_loop = loop
	if _anim_driver:
		_anim_driver.play(0, anim_name, loop, AnimDriverSpine.PlayMode.REPLACE_TRACK)
	elif _anim_mock:
		_anim_mock.play(0, anim_name, loop)


func anim_is_playing(anim_name: StringName) -> bool:
	return _current_anim == anim_name and not _current_anim_finished


func anim_is_finished(anim_name: StringName) -> bool:
	return _current_anim == anim_name and _current_anim_finished


func _on_anim_completed(_track: int, anim_name: StringName) -> void:
	if anim_name == _current_anim:
		_current_anim_finished = true


# =============================================================================
# 伤害接口（受到任意伤害 → 触发重置）
# =============================================================================

func force_close_hit_windows() -> void:
	## 强制关闭幽灵攻击命中检测窗口（见 0.1 节）
	atk_hit_window_open = false


func on_damage_received() -> void:
	## 由攻击命中回调或 EventBus 调用，触发断链重置
	took_damage = true


# =============================================================================
# 辅助方法
# =============================================================================

func get_player_node() -> Node2D:
	if _player != null and is_instance_valid(_player):
		return _player
	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return null
	return players[0] as Node2D


func teleport_to_player_side() -> void:
	## 重置时传送到玩家附近（优先玩家左右上方约 200px，避开碰撞体）
	var p := get_player_node()
	if p == null:
		return
	var base_left: Vector2 = p.global_position + Vector2(-respawn_radius, -respawn_up_offset)
	var base_right: Vector2 = p.global_position + Vector2(respawn_radius, -respawn_up_offset)
	var fallback: Vector2 = p.global_position + Vector2(-player_side_offset, -40.0)

	var candidate: Vector2 = _pick_safe_respawn_point([base_left, base_right], p)
	if candidate == Vector2.ZERO:
		candidate = _pick_safe_respawn_point([base_right, base_left], p)
	if candidate == Vector2.ZERO:
		candidate = fallback
	global_position = candidate


func _pick_safe_respawn_point(bases: Array[Vector2], player: Node2D) -> Vector2:
	for base: Vector2 in bases:
		if _is_respawn_position_clear(base, player):
			return base
		for i: int in range(1, max(1, respawn_probe_tries) + 1):
			var side: float = respawn_probe_side_step * float(i)
			var up: float = respawn_probe_up_step * float(i)
			var c1: Vector2 = base + Vector2(side, -up)
			if _is_respawn_position_clear(c1, player):
				return c1
			var c2: Vector2 = base + Vector2(-side, -up)
			if _is_respawn_position_clear(c2, player):
				return c2
	return Vector2.ZERO


func _is_respawn_position_clear(pos: Vector2, player: Node2D) -> bool:
	var world2d := get_world_2d()
	if world2d == null:
		return true
	var space: PhysicsDirectSpaceState2D = world2d.direct_space_state
	if space == null:
		return true

	var shape: Shape2D = null
	var body_shape := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if body_shape != null:
		shape = body_shape.shape
	if shape == null:
		return true

	var q := PhysicsShapeQueryParameters2D.new()
	q.shape = shape
	q.collide_with_areas = false
	q.collide_with_bodies = true
	# World(1)=1, EnemyBody(3)=4, hazards(6)=32
	q.collision_mask = 1 | 4 | 32
	q.transform = Transform2D(0.0, pos)
	q.exclude = [get_rid()]
	if player != null and is_instance_valid(player):
		q.exclude.append(player.get_rid())

	var hits: Array = space.intersect_shape(q, 8)
	return hits.is_empty()


func is_active_control_slot() -> bool:
	## 仅当本奇美拉占用当前 active_slot 时，才允许移动操控/攻击。
	if not is_linked():
		return false
	var p := get_player_node()
	if p == null or not is_instance_valid(p):
		return false
	if not ("chain_sys" in p):
		return false
	var cs = p.chain_sys
	if cs == null or not ("active_slot" in cs):
		return false
	return int(cs.active_slot) == int(get_linked_slot())


func on_player_interact(_player_ref: Player) -> void:
	## 激活槽位上的 M 键交互：请求攻击。
	if not is_active_control_slot():
		return
	request_attack()


func _set_player_control_frozen(frozen: bool) -> void:
	var player := get_player_node()
	if player != null and player.has_method("set_external_control_frozen"):
		player.call("set_external_control_frozen", frozen)
	control_input_frozen = frozen


func on_chain_attached(slot: int) -> void:
	super.on_chain_attached(slot)
	# 仅当当前切到本奇美拉槽位时冻结玩家移动。
	_set_player_control_frozen(is_active_control_slot())


func on_chain_detached(slot: int) -> void:
	var was_linked: bool = is_linked() and get_linked_slot() == slot
	super.on_chain_detached(slot)
	if was_linked:
		# 断链后恢复；若仍有其他链接但非当前激活槽位，也不应保持冻结。
		_set_player_control_frozen(is_active_control_slot())
		detached_reset_pending = true


func request_attack() -> void:
	## 玩家输入层调用：请求攻击
	attack_requested = true


func resolve_hit_on_targets() -> void:
	## 检测攻击区域内的目标并处理命中效果
	if _attack_area == null:
		return
	var hit := HitData.create(attack_damage, get_player_node(), &"chimera_ghost_hand_l")
	var seen: Dictionary = {}

	var bodies := _attack_area.get_overlapping_bodies()
	for body in bodies:
		if not is_instance_valid(body):
			continue
		var rid_b: RID = body.get_rid()
		if seen.has(rid_b):
			continue
		seen[rid_b] = true
		# 命中 StoneMaskBirdFaceBullet → 反弹（不走 apply_hit）
		if body is StoneMaskBirdFaceBullet:
			body.reflect()
			continue
		if body.has_method("apply_hit"):
			body.call("apply_hit", hit)

	var areas := _attack_area.get_overlapping_areas()
	for area in areas:
		if not is_instance_valid(area):
			continue
		var rid_a: RID = area.get_rid()
		if seen.has(rid_a):
			continue
		seen[rid_a] = true
		var bullet := _resolve_bullet(area)
		if bullet != null:
			bullet.reflect()
			continue
		var target := _resolve_monster(area)
		if target != null:
			target.apply_hit(hit)


func _resolve_monster(area_or_body: Node) -> MonsterBase:
	var cur: Node = area_or_body
	if cur != null and cur.has_method("get_host"):
		cur = cur.call("get_host")
	for _i: int in range(6):
		if cur == null:
			return null
		if cur is MonsterBase:
			return cur as MonsterBase
		cur = cur.get_parent()
	return null


func _resolve_bullet(area_or_body: Node) -> StoneMaskBirdFaceBullet:
	var cur: Node = area_or_body
	for _i: int in range(4):
		if cur == null:
			return null
		if cur is StoneMaskBirdFaceBullet:
			return cur as StoneMaskBirdFaceBullet
		cur = cur.get_parent()
	return null


static func now_ms() -> int:
	return Time.get_ticks_msec()


# =============================================================================
# Spine 事件
# =============================================================================

func _on_spine_event(_a1, _a2 = null, _a3 = null, _a4 = null) -> void:
	var event_name: StringName = _extract_spine_event_name([_a1, _a2, _a3, _a4])
	if event_name == &"":
		return
	match event_name:
		&"hit_on":       ev_hit_on = true;      atk_hit_window_open = true
		&"hit_off":      atk_hit_window_open = false
		&"attack_done":  ev_attack_done = true


func _extract_spine_event_name(args: Array) -> StringName:
	for arg in args:
		if arg == null:
			continue
		if arg is StringName:
			return arg
		if arg is String:
			return StringName(arg)
		if arg.has_method("get_data"):
			var d: Variant = arg.get_data()
			if d != null:
				var n: StringName = _get_obj_name(d)
				if n != &"":
					return n
		var n: StringName = _get_obj_name(arg)
		if n != &"":
			return n
	return &""


func _get_obj_name(obj: Object) -> StringName:
	if obj.has_method("get_name"):
		return StringName(obj.get_name())
	if obj.has_method("getName"):
		return StringName(obj.getName())
	return &""


# =============================================================================
# Mock 驱动时长
# =============================================================================

func _setup_mock_durations() -> void:
	_anim_mock._durations[&"idle_float"] = 1.0
	_anim_mock._durations[&"move_float"] = 0.6
	_anim_mock._durations[&"attack"] = 0.5
	_anim_mock._durations[&"vanish"] = 0.4
	_anim_mock._durations[&"appear"] = 0.4
