extends ChimeraBase
class_name ChimeraNunSnake

## =============================================================================
## ChimeraNunSnake - 修女蛇（Beehave x Spine 行为树 奇美拉攻击型怪物）
## =============================================================================
## 顶层状态：CLOSED_EYE / OPEN_EYE / GUARD_BREAK / WEAK / STUN
## 详见蓝图文档第4~6节。
## 行为由 Beehave 行为树驱动。
## 动画由 AnimDriverSpine（或 AnimDriverMock fallback）驱动。
## =============================================================================

## ===== 顶层模式枚举 =====
enum Mode {
	CLOSED_EYE  = 0,  ## 闭眼系：移动/接敌/闭眼攻击/石化追击
	OPEN_EYE    = 1,  ## 睁眼系：定点攻击/眼球发射/弱点暴露
	GUARD_BREAK = 2,  ## 破防独立状态：enter→loop→出口
	WEAK        = 3,  ## 虚弱：可被链接，结束后链接解除
	STUN        = 4,  ## 眩晕：可被链接，结束后链接解除
}

## ===== 眼球阶段枚举 =====
enum EyePhase {
	SOCKETED     = 0,  ## 眼球在眼窝
	OUTBOUND     = 1,  ## 发射飞出中
	HOVER        = 2,  ## 悬停
	RETARGETING  = 3,  ## 重新锁定目标
	RETURNING    = 4,  ## 正常返航
	FORCE_RECALL = 5,  ## 被 weak/stun/中断 强制召回
}

## ===== 导出参数（通用）=====
@export var detect_player_radius: float = 240.0
## 检测玩家半径（px）

@export var detect_attack_target_radius: float = 240.0
## 检测攻击目标半径（px）

@export var closed_walk_speed: float = 90.0
## 闭眼常规移动速度（px/s）

@export var closed_run_speed: float = 130.0
## 闭眼快速移动速度（px/s）

@export var petrified_target_chase_speed: float = 150.0
## 石化玩家追击速度（px/s）

## ===== 导出参数（状态时长）=====
@export var guard_break_duration_sec: float = 0.8
## 破防状态持续时长（秒）

@export var open_eye_idle_timeout: float = 1.2
## 睁眼 idle 超时（秒）

@export var closed_eye_poll_interval: float = 0.1
## 闭眼感知轮询间隔（秒）

@export var weak_eye_recall_check_interval: float = 1.0
## 虚弱状态下眼球召回检测间隔（秒）

@export var weak_duration: float = 2.5
## 虚弱持续时长（秒）

@export var stun_duration_override: float = 1.2
## 修女蛇眩晕持续时长（秒，覆盖 MonsterBase 默认值）

## ===== 导出参数（攻击 A：僵直攻击）=====
@export var stiff_attack_range: float = 80.0
## 僵直攻击范围（px）

@export var stiff_attack_damage: int = 1
## 僵直攻击伤害

@export var stiff_attack_player_stun_sec: float = 0.5
## 僵直攻击命中后玩家僵直时长（秒）

## ===== 导出参数（攻击 B：发射眼球）=====
@export var eye_projectile_speed: float = 420.0
## 眼球飞行速度（px/s）

@export var eye_projectile_hover_sec: float = 0.5
## 眼球悬停时长（秒）

@export var eye_projectile_retarget_count: int = 3
## 眼球重定向次数

@export var eye_projectile_invincible: bool = true
## 眼球子弹是否无敌（不可被攻击命中）

@export var eye_return_speed: float = 700.0
## 眼球返航速度（px/s）

@export var eye_projectile_max_lifetime_sec: float = 10.0
## 眼球最大存活时长（秒），超时强制销毁

@export var eye_projectile_scene: PackedScene = null
## 眼球子弹实例场景（运行时 spawn）

## ===== 导出参数（攻击 C：锤地）=====
@export var ground_pound_range: float = 110.0
## 锤地攻击范围（px）

@export var ground_pound_damage: int = 1
## 锤地伤害

## ===== 导出参数（攻击 D：甩尾）=====
@export var tail_sweep_range: float = 140.0
## 甩尾攻击范围（px）

@export var tail_sweep_knockback_px: float = 200.0
## 甩尾击退距离（px）

## ===== 内部状态（BT 叶节点直接读写）=====

var mode: int = Mode.CLOSED_EYE
## 当前顶层模式

var eye_phase: int = EyePhase.SOCKETED
## 眼球当前阶段

var facing: int = 1
## 当前朝向（1=右, -1=左）

## ===== 转场锁 =====
var opening_transition_lock: bool = false
## 开眼转场锁：防止 reactive BT 在开眼过程中抢占

var closing_transition_lock: bool = false
## 关眼转场锁：防止 reactive BT 在关眼过程中抢占

## ===== 破防计时 =====
var guard_break_end_ms: int = 0
## 破防状态结束时间戳（ms）

## ===== 攻击命中窗口 =====
var atk_hit_window_open: bool = false
## 攻击命中窗口是否开启（由 atk_hit_on/atk_hit_off Spine 事件驱动）

var eye_hurtbox_enabled: bool = false
## EyeHurtbox 是否激活（由 eye_hurtbox_enable/disable Spine 事件驱动）

## ===== 眼球子弹实例 =====
var _eye_projectile_instance: Node2D = null
## 当前飞出的眼球子弹实例

## ===== Spine 事件标志（_on_spine_event 写入，BT 叶节点读取后立即清除）=====
var ev_eye_hurtbox_enable: bool = false
var ev_eye_hurtbox_disable: bool = false
var ev_atk_hit_on: bool = false
var ev_atk_hit_off: bool = false
var ev_eye_shoot_spawn: bool = false
var ev_guard_break_done: bool = false
var ev_open_to_close_done: bool = false
var ev_close_to_open_done: bool = false

## ===== 动画状态追踪 =====
var _current_anim: StringName = &""
var _current_anim_finished: bool = false
var _current_anim_loop: bool = false

## ===== 动画驱动 =====
var _anim_driver: AnimDriverSpine = null
var _anim_mock: AnimDriverMock = null

## ===== 受击盒引用 =====
var _hurtbox_main: Area2D = null     ## 主 Hurtbox（闭眼时也无效，仅链条溶解）
var _eye_hurtbox: Area2D = null      ## EyeHurtbox（睁眼/破防时有效）
var _ground_pound_hitbox: Area2D = null  ## GroundPoundHitbox
var _detect_area: Area2D = null      ## 感知范围 Area2D

@onready var _spine_sprite: Node = null

## ===== 待处理命中来源记录（破防判断用）=====
var _pending_guard_break_hit: bool = false
## 本帧是否收到了破防来源命中

var _last_eye_hurtbox_hp_hit: bool = false
## 本帧 EyeHurtbox 是否受到 HP 扣减

# =============================================================================
# 生命周期
# =============================================================================

func _ready() -> void:
	species_id = &"chimera_nun_snake"
	attribute_type = AttributeType.LIGHT
	size_tier = SizeTier.MEDIUM
	max_hp = 5
	weak_hp = 1
	# 修女蛇属于 Chimera（entity_type 已在 ChimeraBase._ready 中设置）
	# 但攻击行为按 Monster 处理
	can_be_attacked = true
	has_hp = true

	super._ready()
	add_to_group("chimera_nun_snake")

	_hurtbox_main = get_node_or_null("Hurtbox") as Area2D
	_eye_hurtbox = get_node_or_null("EyeHurtbox") as Area2D
	_ground_pound_hitbox = get_node_or_null("GroundPoundHitbox") as Area2D
	_detect_area = get_node_or_null("DetectArea") as Area2D

	# 初始状态：EyeHurtbox 禁用
	_set_eye_hurtbox_active(false)

	# 订阅光花放电事件（破防来源之一）
	if EventBus:
		EventBus.lightning_flower_release.connect(_on_lightning_flower_release)

	_spine_sprite = get_node_or_null("SpineSprite")
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


func _is_spine_sprite_compatible(node: Node) -> bool:
	if node == null:
		return false
	if String(node.get_class()) == "SpineSprite":
		return true
	return node.has_method("get_animation_state")


func _physics_process(dt: float) -> void:
	if _anim_mock:
		_anim_mock.tick(dt)

	# 虚弱/眩晕倒计时（修女蛇独立管理，不依赖 MonsterBase 默认流）
	if mode == Mode.WEAK:
		_weak_timer -= dt
		if _weak_timer <= 0.0:
			_exit_weak()
	elif mode == Mode.STUN:
		_stun_timer -= dt
		if _stun_timer <= 0.0:
			_exit_stun()

	# 重力
	if not is_on_floor():
		velocity.y += 800.0 * dt

	# 朝向翻转（根据水平速度）
	if velocity.x > 10.0:
		facing = 1
	elif velocity.x < -10.0:
		facing = -1

	# Spine sprite 朝向翻转
	if _spine_sprite != null:
		_spine_sprite.scale.x = float(facing)

	# BT 叶节点通过 move_and_slide 移动；物理更新由 BT 叶节点驱动
	# _do_move 覆写不再由基类调用

# 虚弱/眩晕内部计时
var _weak_timer: float = 0.0
var _stun_timer: float = 0.0

# =============================================================================
# 动画接口（BT 叶节点统一调用）
# =============================================================================

func anim_play(anim_name: StringName, loop: bool, _interruptible: bool = true) -> void:
	## 播放指定动画。叶节点只调这一个接口，不直接碰 Spine。
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


func anim_stop() -> void:
	_current_anim = &""
	_current_anim_finished = true
	if _anim_driver:
		_anim_driver.stop_all()
	elif _anim_mock:
		_anim_mock.stop(0)


func _on_anim_completed(_track: int, anim_name: StringName) -> void:
	if anim_name == _current_anim:
		_current_anim_finished = true


# =============================================================================
# Spine 事件回调
# =============================================================================

func _on_spine_event(_a1, _a2 = null, _a3 = null, _a4 = null) -> void:
	var event_name: StringName = _extract_spine_event_name([_a1, _a2, _a3, _a4])
	if event_name == &"":
		return
	match event_name:
		&"eye_hurtbox_enable":
			ev_eye_hurtbox_enable = true
			_set_eye_hurtbox_active(true)
		&"eye_hurtbox_disable":
			ev_eye_hurtbox_disable = true
			_set_eye_hurtbox_active(false)
		&"atk_hit_on":
			ev_atk_hit_on = true
			atk_hit_window_open = true
		&"atk_hit_off":
			ev_atk_hit_off = true
			atk_hit_window_open = false
		&"eye_shoot_spawn":
			ev_eye_shoot_spawn = true
		&"guard_break_done":
			ev_guard_break_done = true
		&"open_to_close_done":
			ev_open_to_close_done = true
		&"close_to_open_done":
			ev_close_to_open_done = true


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
	if obj == null:
		return &""
	if obj.has_method("get_name"):
		return StringName(obj.get_name())
	if obj.has_method("getName"):
		return StringName(obj.getName())
	return &""

# =============================================================================
# 受击盒控制
# =============================================================================

func _set_eye_hurtbox_active(active: bool) -> void:
	eye_hurtbox_enabled = active
	if _eye_hurtbox == null:
		return
	_eye_hurtbox.monitoring = active
	_eye_hurtbox.monitorable = active
	var shape := _eye_hurtbox.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape:
		shape.disabled = not active


func force_close_hit_windows() -> void:
	## 强制关闭所有命中检测窗口（被打断时确保无残留开窗）
	atk_hit_window_open = false
	_set_eye_hurtbox_active(false)
	if _ground_pound_hitbox:
		_ground_pound_hitbox.monitoring = false


# =============================================================================
# 受击规则（伤害矩阵）
# =============================================================================

func _can_break_closed_guard(weapon_id: StringName) -> bool:
	## 判断来源是否能破防闭眼防御
	return (
		weapon_id == &"ghost_fist"
		or weapon_id == &"chimera_ghost_hand_l"
		or weapon_id == &"lightning_flower"
		or weapon_id == &"lightflower"
	)


func apply_hit(hit: HitData) -> bool:
	if hit == null:
		return false
	if not has_hp or hp <= 0:
		return false

	match mode:
		Mode.CLOSED_EYE:
			# 链条命中：溶解无效，不建链，不扣血
			if hit.weapon_id == &"chain":
				_flash_once()
				return true  # 消耗命中，但无效
			# 普通武器无效
			if not _can_break_closed_guard(hit.weapon_id):
				_play_closed_eye_hit_resist()
				return true
			# 有效破防来源 → 进入 GUARD_BREAK
			_enter_guard_break()
			_flash_once()
			return true

		Mode.OPEN_EYE, Mode.GUARD_BREAK:
			# 仅 EyeHurtbox 命中时有效（由 _last_eye_hurtbox_hp_hit 标记）
			# 本函数只在 EyeHurtbox 路由后才被调用扣血
			if _last_eye_hurtbox_hp_hit:
				_last_eye_hurtbox_hp_hit = false
				if hp_locked:
					_flash_once()
					return true
				hp = max(hp - hit.damage, 0)
				_flash_once()
				if hp <= weak_hp and hp > 0 and not weak:
					# 进入虚弱
					weak = true
					hp_locked = true
					vanish_fusion_count = 0
					_enter_weak()
				elif hp <= 0 and not hp_locked:
					_on_death()
				return true
			# 非 EyeHurtbox 路由：无效
			return false

		Mode.WEAK, Mode.STUN:
			# hp_locked 时普通攻击无效；可被链接（链条路由在 on_chain_hit 中处理）
			_flash_once()
			return true

	return false


func _play_closed_eye_hit_resist() -> void:
	## 闭眼无效受击反馈：不可被普通无效攻击反复打断，但可被破防来源覆盖
	if (
		anim_is_playing(&"closed_eye_hit_resist")
		or anim_is_playing(&"ground_pound")
		or anim_is_playing(&"tail_sweep")
	):
		return
	_flash_once()
	anim_play(&"closed_eye_hit_resist", false, false)


## 由 EyeHurtbox 的 Area2D 信号路由调用（标记本次命中来自 EyeHurtbox）
func mark_eye_hurtbox_hit(hit: HitData) -> bool:
	if not eye_hurtbox_enabled:
		return false
	_last_eye_hurtbox_hp_hit = true
	return apply_hit(hit)


# =============================================================================
# 锁链交互（覆写 ChimeraBase 默认"可直链"行为）
# =============================================================================

func on_chain_hit(player_ref: Node, slot: int) -> int:
	# 修女蛇不可直接链接，只有 weak 或 stun 状态才可链
	match mode:
		Mode.WEAK, Mode.STUN:
			if is_occupied_by_other_chain(slot):
				return 0
			_linked_player = player_ref
			_player = player_ref as Node2D
			return 1  # 可链接
		_:
			# 闭眼时链条仅溶解
			_flash_once()
			return 0


# =============================================================================
# 状态切换（供 BT 叶节点调用）
# =============================================================================

func enter_mode(new_mode: int) -> void:
	## 切换顶层模式（统一入口）
	mode = new_mode
	match new_mode:
		Mode.CLOSED_EYE:
			_set_eye_hurtbox_active(false)
			opening_transition_lock = false
			closing_transition_lock = false
		Mode.OPEN_EYE:
			# EyeHurtbox 由 Spine 事件驱动开启
			opening_transition_lock = false
		Mode.GUARD_BREAK:
			_set_eye_hurtbox_active(true)
			guard_break_end_ms = Time.get_ticks_msec() + int(guard_break_duration_sec * 1000.0)
		Mode.WEAK:
			_enter_weak()
		Mode.STUN:
			_enter_stun()


func _enter_guard_break() -> void:
	mode = Mode.GUARD_BREAK
	_set_eye_hurtbox_active(true)
	guard_break_end_ms = Time.get_ticks_msec() + int(guard_break_duration_sec * 1000.0)
	velocity = Vector2.ZERO
	force_close_hit_windows()
	atk_hit_window_open = false
	# EyeHurtbox 启用（破防阶段暴露弱点）
	eye_hurtbox_enabled = true


func _enter_weak() -> void:
	mode = Mode.WEAK
	_weak_timer = weak_duration
	# 立即终止当前攻击链
	force_close_hit_windows()
	velocity = Vector2.ZERO
	# 若眼球在外，强制召回
	if eye_phase != EyePhase.SOCKETED:
		_force_eye_recall()


func _exit_weak() -> void:
	mode = Mode.CLOSED_EYE
	_set_eye_hurtbox_active(false)
	weak = false
	hp_locked = false
	vanish_fusion_count = 0
	# 状态结束后 chain 链接解除（MonsterBase 规则）
	_release_linked_chain_if_any()


func _enter_stun() -> void:
	mode = Mode.STUN
	_stun_timer = stun_duration_override
	force_close_hit_windows()
	velocity = Vector2.ZERO
	if eye_phase != EyePhase.SOCKETED:
		_force_eye_recall()


func _exit_stun() -> void:
	mode = Mode.CLOSED_EYE
	_set_eye_hurtbox_active(false)
	_release_linked_chain_if_any()


func _force_eye_recall() -> void:
	## 强制眼球召回（进入 FORCE_RECALL 阶段）
	eye_phase = EyePhase.FORCE_RECALL
	if _eye_projectile_instance != null and is_instance_valid(_eye_projectile_instance):
		if _eye_projectile_instance.has_method("force_recall"):
			_eye_projectile_instance.call("force_recall")


func _release_linked_chain_if_any() -> void:
	## 状态结束后解除 chain 链接（按 MonsterBase 规则：weak/stun 结束时解除）
	if not is_linked():
		return
	# 通知玩家端的 chain_sys 解除此槽位的链接
	if _linked_player != null and is_instance_valid(_linked_player):
		var cs: Node = _linked_player.get_node_or_null("Components/ChainSystem")
		if cs != null and cs.has_method("force_detach_from_target"):
			cs.call("force_detach_from_target", self)


func _on_lightning_flower_release(source: Node2D) -> void:
	## 光花放电事件响应：若在闭眼状态则触发破防
	if mode != Mode.CLOSED_EYE:
		return
	if source == null or not is_instance_valid(source):
		return
	# 检查距离（光花须在感知范围内）
	if source.global_position.distance_to(global_position) > detect_player_radius * 1.5:
		return
	_enter_guard_break()


# =============================================================================
# 眼球子弹接口（供 BT 叶节点调用）
# =============================================================================

func spawn_eye_projectile() -> Node2D:
	## 在 eye_shoot_spawn 帧生成眼球子弹
	if eye_projectile_scene == null:
		push_error("[ChimeraNunSnake] eye_projectile_scene 未设置，无法生成眼球")
		return null
	if _eye_projectile_instance != null and is_instance_valid(_eye_projectile_instance):
		# 上一颗眼球未回收，跳过
		return _eye_projectile_instance

	var proj: Node = (eye_projectile_scene as PackedScene).instantiate()
	var proj2d := proj as Node2D
	if proj2d != null:
		# 出生点：EyeHurtbox 骨骼位置（或 fallback 到自身位置）
		var spawn_pos: Vector2 = _get_eye_socket_world_pos()
		proj2d.global_position = spawn_pos
		if proj.has_method("setup"):
			proj.call("setup", self)
	get_parent().add_child(proj)
	_eye_projectile_instance = proj2d
	eye_phase = EyePhase.OUTBOUND
	return proj2d


func _get_eye_socket_world_pos() -> Vector2:
	## 获取眼球发射点（骨骼挂点或 fallback）
	if _anim_driver != null:
		var bone_pos: Vector2 = _anim_driver.get_bone_world_position("bone_eye_socket")
		if bone_pos != Vector2.ZERO:
			return bone_pos
	if _eye_hurtbox != null:
		return _eye_hurtbox.global_position
	return global_position + Vector2(0.0, -40.0)


func get_eye_socket_world_pos() -> Vector2:
	return _get_eye_socket_world_pos()


func notify_eye_returned() -> void:
	## 由眼球子弹在到达眼窝后调用，通知修女蛇眼球已归位
	eye_phase = EyePhase.SOCKETED
	_eye_projectile_instance = null


# =============================================================================
# 感知接口（供 BT 条件节点调用）
# =============================================================================

func get_player() -> Node2D:
	## 优先从 DetectArea 获取，否则从组中获取
	if _detect_area != null:
		for body in _detect_area.get_overlapping_bodies():
			if body.is_in_group(MonsterBase.ATTACK_TARGET_GROUP):
				return body as Node2D
	var players: Array = get_tree().get_nodes_in_group("player")
	if not players.is_empty():
		return players[0] as Node2D
	return null


func get_petrified_player() -> Node2D:
	## 检测是否有石化玩家
	var players: Array = get_tree().get_nodes_in_group("player")
	for p in players:
		if p.has_method("is_petrified") and p.call("is_petrified"):
			return p as Node2D
	return null


func is_player_in_range(range_px: float) -> bool:
	## 检测玩家是否在指定范围内（只检查水平距离）
	var player: Node2D = get_player()
	if player == null:
		return false
	return absf(player.global_position.x - global_position.x) <= range_px


func is_player_in_detect_area() -> bool:
	return get_player() != null


# =============================================================================
# 静态辅助
# =============================================================================

static func now_ms() -> int:
	return Time.get_ticks_msec()


# =============================================================================
# Mock 驱动时长（无 Spine 时 fallback）
# =============================================================================

func _setup_mock_durations() -> void:
	_anim_mock._durations[&"closed_eye_idle"] = 1.0
	_anim_mock._durations[&"closed_eye_walk"] = 0.8
	_anim_mock._durations[&"closed_eye_run"] = 0.6
	_anim_mock._durations[&"closed_eye_hit_resist"] = 0.3
	_anim_mock._durations[&"close_to_open"] = 0.5
	_anim_mock._durations[&"open_eye_idle"] = 1.0
	_anim_mock._durations[&"stiff_attack"] = 0.5
	_anim_mock._durations[&"shoot_eye_start"] = 0.4
	_anim_mock._durations[&"shoot_eye_loop"] = 1.0
	_anim_mock._durations[&"shoot_eye_end"] = 0.4
	_anim_mock._durations[&"shoot_eye_recall"] = 0.4
	_anim_mock._durations[&"open_eye_to_close"] = 0.5
	_anim_mock._durations[&"guard_break_enter"] = 0.4
	_anim_mock._durations[&"guard_break_loop"] = 1.0
	_anim_mock._durations[&"ground_pound"] = 0.6
	_anim_mock._durations[&"tail_sweep"] = 0.5
	_anim_mock._durations[&"weak"] = 0.4
	_anim_mock._durations[&"weak_loop"] = 1.0
	_anim_mock._durations[&"stun"] = 0.4
	_anim_mock._durations[&"stun_loop"] = 1.0
