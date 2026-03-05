extends MonsterBase
class_name Mollusc

## =============================================================================
## Mollusc - 软体虫（石眼虫弹翻后逃出的软体阶段，独立实例）
## =============================================================================
## 优先级：回壳 > 攻击玩家 > 逃跑
## 逃跑方向：前向墙/断崖检测，死路则掉头
## 回壳闭环：检测到空壳（group "stoneeyebug_shell_empty"）则回去销毁自身
## =============================================================================

# ===== 导出参数（策划可调）=====

@export var escape_speed: float = 140.0
## 逃跑速度（px/s）

@export var escape_dist: float = 300.0
## 每轮逃跑距离（px）

@export var threat_dist: float = 200.0
## 玩家威胁距离（px），玩家进入此范围则重新规划逃跑

@export var attack_range: float = 120.0
## 攻击触发范围（px）

@export var attack_cd: float = 2.0
## 攻击冷却（秒）

@export var player_stone_stun: float = 2.0
## attack_stone 命中后玩家僵直时长（秒）

@export var knockback_strength: float = 350.0
## attack_lick 击退强度（velocity px/s）

@export var gravity: float = 800.0
## 重力加速度（px/s²）

@export var wall_check_forward: float = 96.0
## 前向撞墙检测距离（px）

@export var floor_check_forward: float = 16.0
## 断崖检测的前向探针偏移（px）

@export var floor_check_down: float = 24.0
## 断崖检测的向下探针长度（px）

@export var breakout_overtake_px: float = 50.0
## 破局连段后继续前冲的越位距离（相对玩家，px）

# ===== 内部状态 =====

## 家园空壳节点（由 StoneEyeBug 调用 set_home_shell 设置）
var home_shell: Node2D = null

## 逃跑剩余距离
var escape_remaining: float = 0.0

## 逃跑方向（水平，1 或 -1）
var escape_dir_x: int = 1

## 攻击冷却截止时间（ms）— 软体攻击无 2s 冷却（蓝图确认），留接口方便未来调整
var next_attack_end_ms: int = 0

## 是否正在执行攻击（供 BT 叶节点使用）
var is_attacking: bool = false

## 攻击命中检测窗口（见 0.1 节 ForceCloseHitWindows 安全机制）
var atk1_window_open: bool = false
var atk2_window_open: bool = false

## Spine 事件标志（_on_spine_event 置位，BT 叶节点读取后清零）
var ev_atk1_hit_on: bool = false
var ev_atk1_hit_off: bool = false
var ev_atk2_hit_on: bool = false
var ev_atk2_hit_off: bool = false

## 受击硬直标记（防止受击打断攻击时判定残留）
var is_hurt: bool = false
var hurt_lock_t: float = 0.0

## 破局状态：左右受压卡死时触发（强制朝玩家侧移动并立即可攻击）
var forced_breakout_active: bool = false
var breakout_post_combo_active: bool = false
var breakout_target_player: Node2D = null
var breakout_target_x: float = 0.0


# ===== 动画状态追踪 =====

var _current_anim: StringName = &""
var _current_anim_finished: bool = false
var _current_anim_loop: bool = false

# ===== 动画驱动 =====

var _anim_driver: AnimDriverSpine = null
var _anim_mock: AnimDriverMock = null

@onready var _spine_sprite: Node = null
@onready var _floor_ray_front: RayCast2D = get_node_or_null("FloorRayFront")
@onready var _wall_ray_front: RayCast2D = get_node_or_null("WallRayFront")

# ===== 生命周期 =====

func _ready() -> void:
	species_id = &"mollusc"
	attribute_type = AttributeType.DARK
	size_tier = SizeTier.SMALL
	max_hp = 3
	weak_hp = 1
	super._ready()
	add_to_group("mollusc")

	# 初始逃跑方向：随机
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	escape_dir_x = 1 if rng.randi() % 2 == 0 else -1
	escape_remaining = 0.0

	_spine_sprite = get_node_or_null("SpineSprite")
	_setup_front_rays()
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


func _setup_front_rays() -> void:
	## 运行时兜底：确保前向检测射线启用（避免场景勾选遗漏导致不掉头）
	if _wall_ray_front != null:
		_wall_ray_front.enabled = true
		_wall_ray_front.collision_mask = 1  # World(1)
	if _floor_ray_front != null:
		_floor_ray_front.enabled = true
		_floor_ray_front.collision_mask = 1  # World(1)


func _physics_process(dt: float) -> void:
	if light_counter > 0.0:
		light_counter -= dt
		light_counter = max(light_counter, 0.0)
	_thunder_processed_this_frame = false

	if _anim_mock:
		_anim_mock.tick(dt)

	if weak and weak_stun_t > 0.0:
		weak_stun_t = max(weak_stun_t - dt, 0.0)
		if weak_stun_t <= 0.0:
			_restore_from_weak()

	# 受击硬直计时
	if hurt_lock_t > 0.0:
		hurt_lock_t = max(hurt_lock_t - dt, 0.0)
		if hurt_lock_t <= 0.0:
			is_hurt = false

	# 移动由 BT 叶节点控制；apply_gravity 在 Act_MolluscEscape 内处理


func _do_move(_dt: float) -> void:
	pass


# =============================================================================
# 动画接口
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
# 辅助方法（BT 叶节点调用）
# =============================================================================

func force_close_hit_windows() -> void:
	## 强制关闭所有命中检测窗口（见 0.1 节）
	atk1_window_open = false
	atk2_window_open = false


func apply_hit(hit: HitData) -> bool:
	## 受击处理：仅受击反馈，不走 HP 死亡语义。
	## 设计确认：Mollusc 生命终结路径为回壳/融合回收，不因常规受击直接死亡。
	if hit == null:
		return false
	if hurt_lock_t <= 0.0:
		_do_hurt()
	else:
		_flash_once()
	return true


func _do_hurt() -> void:
	force_close_hit_windows()
	is_hurt = true
	hurt_lock_t = 0.3  # 300ms 防抽搐
	anim_play(&"hurt", false, false)


func set_home_shell(shell: Node2D) -> void:
	home_shell = shell


func find_empty_shell() -> Node2D:
	## 在场景中找到空壳节点（group: stoneeyebug_shell_empty）
	var shells := get_tree().get_nodes_in_group("stoneeyebug_shell_empty")
	if shells.is_empty():
		return null
	# 返回最近的空壳
	var nearest: Node2D = null
	var nearest_dist := INF
	for s in shells:
		if not is_instance_valid(s):
			continue
		var sn := s as Node2D
		if sn == null:
			continue
		var d := global_position.distance_to(sn.global_position)
		if d < nearest_dist:
			nearest_dist = d
			nearest = sn
	return nearest


func is_player_in_attack_range() -> bool:
	if forced_breakout_active:
		return get_primary_player_in_range(attack_range) != null
	return _get_attack_target_in_range(attack_range) != null


func is_player_near_threat() -> bool:
	return _get_attack_target_in_range(threat_dist) != null


func get_player() -> Node2D:
	## Beehave 优先：仅在“攻击分支已判定进入攻击范围”时再取攻击目标。
	## 这里严格限制为 attack_range 内目标，避免主动寻敌改变行为树语义。
	if forced_breakout_active:
		var primary := get_primary_player_in_range(attack_range)
		if primary != null:
			return primary
	return _get_attack_target_in_range(attack_range)


func get_primary_player_in_range(range_limit: float) -> Node2D:
	if range_limit <= 0.0:
		return null
	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return null
	var nearest: Node2D = null
	var nearest_dist := INF
	for p in players:
		if not is_instance_valid(p):
			continue
		var node := p as Node2D
		if node == null:
			continue
		var d := global_position.distance_to(node.global_position)
		if d > range_limit:
			continue
		if d < nearest_dist:
			nearest_dist = d
			nearest = node
	return nearest


func _get_attack_target_in_range(range_limit: float) -> Node2D:
	if range_limit <= 0.0:
		return null
	var targets := get_tree().get_nodes_in_group(ATTACK_TARGET_GROUP)
	if targets.is_empty():
		targets = get_tree().get_nodes_in_group("player")
	if targets.is_empty():
		return null

	var nearest: Node2D = null
	var nearest_dist := INF
	for t in targets:
		if not is_instance_valid(t):
			continue
		var n := t as Node2D
		if n == null:
			continue
		var d := global_position.distance_to(n.global_position)
		if d > range_limit:
			continue
		if d < nearest_dist:
			nearest_dist = d
			nearest = n
	return nearest


func is_wall_ahead() -> bool:
	## 检测正前方是否有墙（RayCast2D）
	if _wall_ray_front != null and _wall_ray_front.enabled:
		_wall_ray_front.target_position = Vector2(escape_dir_x * wall_check_forward, 0.0)
		_wall_ray_front.force_raycast_update()
		return _wall_ray_front.is_colliding()

	# fallback：即便 RayCast 节点失效，也用空间射线检测前墙
	var from: Vector2 = global_position + Vector2(0.0, -8.0)
	var to: Vector2 = from + Vector2(float(escape_dir_x) * wall_check_forward, 0.0)
	return _ray_hits_world(from, to)


func is_floor_ahead() -> bool:
	## 检测正前方是否有地面（防止走下断崖）
	if _floor_ray_front != null and _floor_ray_front.enabled:
		_floor_ray_front.target_position = Vector2(escape_dir_x * floor_check_forward, floor_check_down)
		_floor_ray_front.force_raycast_update()
		return _floor_ray_front.is_colliding()

	# fallback：前方探针点向下射线检测地面
	var probe: Vector2 = global_position + Vector2(float(escape_dir_x) * floor_check_forward, 0.0)
	var to: Vector2 = probe + Vector2(0.0, floor_check_down)
	return _ray_hits_world(probe, to)


func _ray_hits_world(from: Vector2, to: Vector2) -> bool:
	var world2d := get_world_2d()
	if world2d == null:
		return false
	var space: PhysicsDirectSpaceState2D = world2d.direct_space_state
	if space == null:
		return false
	var q := PhysicsRayQueryParameters2D.create(from, to)
	q.collide_with_bodies = true
	q.collide_with_areas = false
	q.collision_mask = 1  # World(1)
	q.exclude = [get_rid()]
	var hit: Dictionary = space.intersect_ray(q)
	return not hit.is_empty()


func plan_escape_if_player_near() -> void:
	## 若威胁范围内存在攻击目标则重新规划逃跑路线
	if forced_breakout_active:
		var forced_player := get_primary_player_in_range(threat_dist * 1.5)
		if forced_player != null:
			escape_dir_x = 1 if forced_player.global_position.x >= global_position.x else -1
			if escape_remaining <= 0.0:
				escape_remaining = escape_dist
		return
	var player := _get_attack_target_in_range(threat_dist)
	if player == null:
		return
	# 逃离目标：往目标反方向
	var dx := global_position.x - player.global_position.x
	escape_dir_x = 1 if dx >= 0.0 else -1
	# 仅在未处于“逃跑段”时装填距离，避免每帧重置导致 escape_dist 永远跑不完。
	if escape_remaining <= 0.0:
		escape_remaining = escape_dist


func should_trigger_forced_breakout() -> bool:
	if forced_breakout_active:
		return false
	var player := get_primary_player_in_range(threat_dist * 1.5)
	if player == null:
		return false
	if not _has_pressure_on_side(-1):
		return false
	if not _has_pressure_on_side(1):
		return false
	return true


func trigger_forced_breakout() -> void:
	var player := get_primary_player_in_range(threat_dist * 1.5)
	if player == null:
		return
	forced_breakout_active = true
	breakout_post_combo_active = false
	breakout_target_player = player
	next_attack_end_ms = 0
	escape_dir_x = 1 if player.global_position.x >= global_position.x else -1
	escape_remaining = max(escape_remaining, escape_dist)


func begin_breakout_post_combo(player: Node2D) -> void:
	if not forced_breakout_active:
		return
	if player == null or not is_instance_valid(player):
		player = get_primary_player_in_range(threat_dist * 2.0)
	if player == null:
		clear_forced_breakout()
		return
	breakout_target_player = player
	breakout_post_combo_active = true
	escape_dir_x = 1 if breakout_target_player.global_position.x >= global_position.x else -1
	breakout_target_x = breakout_target_player.global_position.x + float(escape_dir_x) * breakout_overtake_px


func update_breakout_post_combo() -> void:
	if not breakout_post_combo_active:
		return
	if breakout_target_player == null or not is_instance_valid(breakout_target_player):
		clear_forced_breakout()
		return
	if escape_dir_x > 0 and global_position.x >= breakout_target_x:
		clear_forced_breakout()
	elif escape_dir_x < 0 and global_position.x <= breakout_target_x:
		clear_forced_breakout()


func clear_forced_breakout() -> void:
	forced_breakout_active = false
	breakout_post_combo_active = false
	breakout_target_player = null
	breakout_target_x = 0.0


func _has_pressure_on_side(side: int) -> bool:
	if _is_world_blocked_on_side(side):
		return true
	return _has_target_on_side(side)


func _is_world_blocked_on_side(side: int) -> bool:
	if side == 0:
		return false
	var dir := 1 if side > 0 else -1
	var from: Vector2 = global_position + Vector2(0.0, -8.0)
	var to: Vector2 = from + Vector2(float(dir) * wall_check_forward, 0.0)
	return _ray_hits_world(from, to)


func _has_target_on_side(side: int) -> bool:
	if side == 0:
		return false
	var dir := 1 if side > 0 else -1
	var targets := get_tree().get_nodes_in_group(ATTACK_TARGET_GROUP)
	if targets.is_empty():
		targets = get_tree().get_nodes_in_group("player")
	for t in targets:
		if not is_instance_valid(t):
			continue
		var n := t as Node2D
		if n == null:
			continue
		var dx := n.global_position.x - global_position.x
		if absf(dx) > threat_dist * 1.5:
			continue
		if dx == 0.0:
			continue
		if signf(dx) == float(dir):
			return true
	return false


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
		&"atk1_hit_on":  ev_atk1_hit_on = true;  atk1_window_open = true
		&"atk1_hit_off": ev_atk1_hit_off = true; atk1_window_open = false
		&"atk2_hit_on":  ev_atk2_hit_on = true;  atk2_window_open = true
		&"atk2_hit_off": ev_atk2_hit_off = true; atk2_window_open = false


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
	_anim_mock._durations[&"idle"] = 1.0
	_anim_mock._durations[&"run"] = 0.5
	_anim_mock._durations[&"enter_shell"] = 0.6
	_anim_mock._durations[&"attack_stone"] = 0.6
	_anim_mock._durations[&"attack_lick"] = 0.5
	_anim_mock._durations[&"hurt"] = 0.3
	_anim_mock._durations[&"weak_stun"] = 0.35      # 入场眩晕（一次）
	_anim_mock._durations[&"weak_stun_loop"] = 1.0  # 虚弱眩晕循环
