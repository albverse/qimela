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

@export var shell_return_idle_delay: float = 5.0
## Idle 连续超过该时长后，才允许进入“检测空壳并回壳”分支（秒）

@export var shell_return_spawn_delay: float = 10.0
## 生成后至少经过该时长，才允许回壳检测（秒）

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

## LightFlower 触发的“弱眩晕”通道（与 weak_stun 动画/时序统一）
var lightflower_weak_stun_active: bool = false

## 破局状态：左右受压卡死时触发（强制朝玩家侧移动并立即可攻击）
var forced_breakout_active: bool = false
var breakout_post_combo_active: bool = false
var breakout_target_player: Node2D = null
var breakout_target_x: float = 0.0

## Idle 受击应激逃跑（一次性请求）
var _idle_state_active: bool = false
var _idle_hit_escape_requested: bool = false
var _idle_elapsed_sec: float = 0.0
var _spawn_elapsed_sec: float = 0.0

## 生成入场锁：先播 enter，结束后才进入常规 BT 行为
var spawn_enter_active: bool = true

## 回壳承诺：开始回壳后，屏蔽”玩家威胁触发逃跑”分支，直到回壳成功或判定路阻。
var shell_return_committed: bool = false

## 入壳无敌锁：进入 ENTER_SHELL/FLIP_TO_NORMAL 阶段后启用。
## 双重保护：① apply_hit/on_chain_hit 忽略所有受击（动画不被覆盖）
##           ② CondMolluscPlayerInRange 返回 FAILURE（Seq_Attack 无法打断）
## 由 ActMolluscReturnShell 在 dist<=16 时设为 true，interrupt() 时清除。
var is_entering_shell: bool = false


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
	if _is_spine_sprite_compatible(_spine_sprite):
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

	spawn_enter_active = true
	anim_play(&"enter", false, false)


func _setup_front_rays() -> void:
	## 运行时兜底：确保前向检测射线启用（避免场景勾选遗漏导致不掉头）
	if _wall_ray_front != null:
		_wall_ray_front.enabled = true
		_wall_ray_front.collision_mask = 1  # World(1)
	if _floor_ray_front != null:
		_floor_ray_front.enabled = true
		_floor_ray_front.collision_mask = 1  # World(1)


func _is_spine_sprite_compatible(node: Node) -> bool:
	if node == null:
		return false
	if String(node.get_class()) == "SpineSprite":
		return true
	# 兜底：某些运行时/封装层 class 名不稳定，改按能力探测。
	return node.has_method("get_animation_state")


func _physics_process(dt: float) -> void:
	if light_counter > 0.0:
		light_counter -= dt
		light_counter = max(light_counter, 0.0)
	_thunder_processed_this_frame = false

	if _anim_mock:
		_anim_mock.tick(dt)

	var weak_channel_active: bool = _is_weak_stun_channel_active()
	if weak_channel_active and weak_stun_t > 0.0:
		weak_stun_t = max(weak_stun_t - dt, 0.0)
	if weak_channel_active and weak_stun_t <= 0.0:
		if weak:
			_restore_from_weak()
		else:
			# LightFlower 弱通道结束时同样必须解链，保持“弱/晕恢复即断链”的统一玩法规则。
			_release_linked_chains()
		# 与 weak 恢复同步清理 lightflower 通道，避免“weak 已恢复但弱眩晕通道残留”导致长时间 act_weakstun。
		lightflower_weak_stun_active = false

	# 受击硬直计时
	if hurt_lock_t > 0.0:
		hurt_lock_t = max(hurt_lock_t - dt, 0.0)
		if hurt_lock_t <= 0.0:
			is_hurt = false

	# 眩晕计时：弱眩晕通道激活时不再倒计时 stunned_t，避免链被误释放。
	if weak_channel_active:
		stunned_t = 0.0
	elif stunned_t > 0.0:
		stunned_t = maxf(stunned_t - dt, 0.0)
		if stunned_t <= 0.0:
			_release_linked_chains()

	# 时间计时
	_spawn_elapsed_sec += dt
	if _idle_state_active:
		_idle_elapsed_sec += dt
	else:
		_idle_elapsed_sec = 0.0

	# 移动由 BT 叶节点控制；apply_gravity 在 Act_MolluscEscape 内处理


func _do_move(_dt: float) -> void:
	pass


func _is_weak_stun_channel_active() -> bool:
	return weak or lightflower_weak_stun_active


func is_stunned() -> bool:
	## Mollusc 统一眩晕语义：普通 stunned_t + weak_stun 通道都视为可链接/不可行动。
	return stunned_t > 0.0 or _is_weak_stun_channel_active()


func get_weak_state() -> bool:
	## 给 ChainSystem 的“目标是否不可动”判定使用：LightFlower weak 通道也算弱态。
	return _is_weak_stun_channel_active()


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
	# 入壳无敌阶段：完全免疫所有受击，enter_shell/flip_to_normal 不可被覆盖。
	if is_entering_shell:
		return false
	if hurt_lock_t <= 0.0:
		_do_hurt()
	else:
		_flash_once()
	_register_idle_hit_escape(hit)
	return true


func on_chain_hit(player_ref: Node, _slot: int) -> int:
	## Mollusc 特例：LightFlower weak 通道也允许被链接，避免”看起来眩晕却不能链”。
	# 入壳无敌阶段：链命中完全忽略。
	if is_entering_shell:
		return 0
	if weak or lightflower_weak_stun_active or stunned_t > 0.0:
		_linked_player = player_ref
		return 1

	# 与 apply_hit 路径统一受击演出：玩家链命中在不可链接时也应触发 hurt 动画。
	take_damage(1)
	if hurt_lock_t <= 0.0:
		_do_hurt()
	else:
		_flash_once()
	return 0


func on_chain_attached(slot: int) -> void:
	## Mollusc 特例：同一槽位重复 attach 时不重复延长眩晕。
	## 仅收敛本体虫链路，避免影响其它怪物的通用链路时序。
	if _linked_slots.is_empty():
		if _hurtbox != null:
			_hurtbox_original_layer = _hurtbox.collision_layer
			_hurtbox.collision_layer = 0

	var is_new_slot: bool = not _linked_slots.has(slot)
	if is_new_slot:
		_linked_slots.append(slot)
	_linked_slot = slot

	if is_new_slot:
		if weak or lightflower_weak_stun_active:
			weak_stun_t += weak_stun_extend_time
		elif stunned_t > 0.0:
			stunned_t += weak_stun_extend_time

	_flash_once()


func _do_hurt() -> void:
	force_close_hit_windows()
	is_hurt = true
	hurt_lock_t = 0.3  # 300ms 防抽搐
	anim_play(&"hurt", false, false)


func set_idle_state_active(active: bool) -> void:
	_idle_state_active = active


func has_idle_hit_escape_request() -> bool:
	return _idle_hit_escape_requested


func clear_idle_hit_escape_request() -> void:
	_idle_hit_escape_requested = false


func finish_spawn_enter() -> void:
	if not spawn_enter_active:
		return
	spawn_enter_active = false
	if not is_hurt and not anim_is_playing(&"idle"):
		anim_play(&"idle", true, true)


func _register_idle_hit_escape(hit: HitData) -> void:
	if not _idle_state_active:
		return
	var attack_dir_x := 0.0
	if hit != null and hit.source != null and is_instance_valid(hit.source):
		var src := hit.source as Node2D
		if src != null:
			attack_dir_x = signf(src.global_position.x - global_position.x)
	if attack_dir_x == 0.0:
		attack_dir_x = float(escape_dir_x)
	escape_dir_x = -1 if attack_dir_x > 0.0 else 1
	escape_remaining = max(escape_remaining, escape_dist)
	_idle_hit_escape_requested = true


func is_shell_return_window_open() -> bool:
	## 生成超过 spawn_delay 秒 OR 发呆超过 idle_delay 秒，均可触发（OR 逻辑）
	var spawn_ok: bool = shell_return_spawn_delay <= 0.0 or _spawn_elapsed_sec >= shell_return_spawn_delay
	var idle_ok: bool = shell_return_idle_delay <= 0.0 or _idle_elapsed_sec >= shell_return_idle_delay
	return spawn_ok or idle_ok


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


func find_new_shell() -> Node2D:
	## 在场景中找到非 home_shell 的最近空壳（group: stoneeyebug_shell_empty）
	var shells := get_tree().get_nodes_in_group("stoneeyebug_shell_empty")
	if shells.is_empty():
		return null
	var nearest: Node2D = null
	var nearest_dist := INF
	for s in shells:
		if not is_instance_valid(s):
			continue
		var sn := s as Node2D
		if sn == null:
			continue
		if sn == home_shell:
			continue
		var d := global_position.distance_to(sn.global_position)
		if d < nearest_dist:
			nearest_dist = d
			nearest = sn
	return nearest


func set_shell_return_committed(active: bool) -> void:
	## ⚠️ 设计冻结 — DO NOT MODIFY — BUG FIX 2025-03-07
	## shell_return_committed 是单向标记（one-way latch）：
	##   一旦设为 true（回壳决策已触发），永远不允许回退为 false。
	##   原因：若允许回退，interrupt()/路阻 FAILURE 会重新开放 Seq_Escape，
	##   导致"回壳决策后仍能逃跑"的 BUG（违反设计规则：决策一旦做出不可撤销）。
	##   唯一例外：queue_free() 调用前的最终清理（mollusc 即将销毁，无实际影响）。
	if shell_return_committed and not active:
		# 单向锁：已承诺则拒绝回退
		return
	shell_return_committed = active
	if active:
		# 回壳承诺生效后，清理 Idle 受击逃跑请求，防止被 Seq_IdleHitEscape 抢占到逃跑分支。
		clear_idle_hit_escape_request()


func is_shell_return_committed() -> bool:
	return shell_return_committed


func set_entering_shell(active: bool) -> void:
	is_entering_shell = active


func is_shell_return_path_blocked(target_shell: Node2D) -> bool:
	if target_shell == null or not is_instance_valid(target_shell):
		return true
	var dx: float = target_shell.global_position.x - global_position.x
	if absf(dx) <= 2.0:
		return false
	escape_dir_x = 1 if dx >= 0.0 else -1
	if is_wall_ahead():
		return true
	if not is_floor_ahead():
		return true
	return false


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
		if breakout_post_combo_active:
			if escape_remaining <= 0.0:
				escape_remaining = escape_dist
			return
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




func should_flip_on_wall() -> bool:
	if not breakout_post_combo_active:
		return true
	if breakout_target_player == null or not is_instance_valid(breakout_target_player):
		return true
	# 破局越位阶段：默认不因前墙掉头，除非玩家后方同向也有墙（确认已无法越位）
	return _is_wall_behind_breakout_player()


func _is_wall_behind_breakout_player() -> bool:
	if breakout_target_player == null or not is_instance_valid(breakout_target_player):
		return false
	var from: Vector2 = breakout_target_player.global_position + Vector2(0.0, -8.0)
	var check_dist: float = maxf(wall_check_forward, breakout_overtake_px + 8.0)
	var to: Vector2 = from + Vector2(float(escape_dir_x) * check_dist, 0.0)
	return _ray_hits_world(from, to)

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


func on_light_exposure(remaining_time: float) -> void:
	super.on_light_exposure(remaining_time)
	if remaining_time <= 0.0:
		return
	# LightFlower 命中后走“弱眩晕”通道：时长与动画流程统一到 weak_stun 体系。
	lightflower_weak_stun_active = true
	weak_stun_t = max(weak_stun_t, weak_stun_time)
	# 若此前处于普通眩晕，清空其计时，避免两套眩晕并行造成表现不一致。
	stunned_t = 0.0


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
	_anim_mock._durations[&"enter"] = 0.45
	_anim_mock._durations[&"idle"] = 1.0
	_anim_mock._durations[&"run"] = 0.5
	_anim_mock._durations[&"enter_shell"] = 0.6
	# NOTE: flip_to_normal 属于 StoneEyeBug 的 Spine 骨架，Mollusc 无此动画（FIX-C）。
	_anim_mock._durations[&"attack_stone"] = 0.6
	_anim_mock._durations[&"attack_lick"] = 0.5
	_anim_mock._durations[&"hurt"] = 0.3
	_anim_mock._durations[&"weak_stun"] = 0.35      # 入场眩晕（一次）
	_anim_mock._durations[&"weak_stun_loop"] = 1.0  # 虚弱眩晕循环
