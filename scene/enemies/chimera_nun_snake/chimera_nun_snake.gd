extends ChimeraBase
class_name ChimeraNunSnake

## =============================================================================
## ChimeraNunSnake - 修女蛇（Beehave x Spine 行为树 奇美拉攻击型怪物）
## 蓝图版本：v0.7
## =============================================================================
## 实体类型：CHIMERA（继承 ChimeraBase），但战斗行为按 Monster 攻击型处理。
## 链条规则走 Monster 逻辑：默认不可直链，只有 weak / stunned 可链。
## 顶层状态：CLOSED_EYE / OPEN_EYE / GUARD_BREAK / WEAK / STUN
## 行为由 Beehave 行为树驱动，动画由 AnimDriverSpine（或 Mock fallback）驱动。
## 移动完全由 BT 叶节点控制（_physics_process 不处理移动和重力）。
## =============================================================================

## ===== 攻击目标组（与 MonsterBase 保持一致）=====
const ATTACK_TARGET_GROUP: StringName = &"enemy_attack_target"

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

# =============================================================================
# 导出参数
# =============================================================================

## --- 通用参数 ---
@export var detect_player_radius: float = 240.0
@export var detect_attack_target_radius: float = 240.0
@export var closed_walk_speed: float = 90.0
@export var closed_run_speed: float = 130.0
@export var petrified_target_chase_speed: float = 150.0

## --- 状态时长参数 ---
@export var guard_break_duration_sec: float = 0.8
@export var open_eye_idle_timeout: float = 1.2
@export var closed_eye_poll_interval: float = 0.1
@export var weak_eye_recall_check_interval: float = 1.0
@export var weak_duration: float = 2.5
@export var stun_duration_override: float = 1.2

## --- 攻击A：僵直攻击 ---
@export var stiff_attack_range: float = 80.0
@export var stiff_attack_damage: int = 1
@export var stiff_attack_player_stun_sec: float = 0.5

## --- 攻击B：发射眼球 ---
@export var eye_projectile_speed: float = 420.0
@export var eye_projectile_hover_sec: float = 0.5
@export var eye_projectile_retarget_count: int = 3
@export var eye_return_speed: float = 700.0
@export var eye_projectile_max_lifetime_sec: float = 10.0
@export var eye_projectile_scene: PackedScene = null

## --- 攻击C：锤地 ---
@export var ground_pound_range: float = 110.0
@export var ground_pound_damage: int = 1

## --- 攻击D：甩尾 ---
@export var tail_sweep_range: float = 140.0
@export var tail_sweep_knockback_px: float = 200.0

## --- 光照系统（MonsterBase 等价）---
@export var light_receiver_path: NodePath = ^"LightReceiver"
@export var light_counter_max: float = 10.0

## --- 受击参数 ---
@export var hit_stun_time: float = 0.1

# =============================================================================
# 内部状态（BT 叶节点直接读写）
# =============================================================================

var mode: int = Mode.CLOSED_EYE
var eye_phase: int = EyePhase.SOCKETED
var facing: int = 1

## 转场锁
var opening_transition_lock: bool = false
var closing_transition_lock: bool = false

## 破防计时
var guard_break_end_ms: int = 0

## 攻击命中窗口（由 atk_hit_on/atk_hit_off Spine 事件驱动）
var atk_hit_window_open: bool = false

## EyeHurtbox 激活状态
var eye_hurtbox_enabled: bool = false

## 虚弱/眩晕内部计时
var _weak_timer: float = 0.0
var _stun_timer: float = 0.0

## 光照系统（MonsterBase 等价）
var light_counter: float = 0.0
var _thunder_processed_this_frame: bool = false

## 链接槽位列表（MonsterBase 等价：支持多条链）
var _linked_slots: Array[int] = []

## 眼球子弹实例
var _eye_projectile_instance: Node2D = null

# =============================================================================
# Spine 事件标志（_on_spine_event 写入，BT 叶节点读取后立即清除）
# =============================================================================
var ev_eye_hurtbox_enable: bool = false
var ev_eye_hurtbox_disable: bool = false
var ev_atk_hit_on: bool = false
var ev_atk_hit_off: bool = false
var ev_eye_shoot_spawn: bool = false
var ev_guard_break_enter_done: bool = false
var ev_open_to_close_done: bool = false
var ev_close_to_open_done: bool = false
var ev_tail_sweep_transition_done: bool = false

# =============================================================================
# 动画状态追踪
# =============================================================================
var _current_anim: StringName = &""
var _current_anim_finished: bool = false
var _current_anim_loop: bool = false

# =============================================================================
# 动画驱动
# =============================================================================
var _anim_driver: AnimDriverSpine = null
var _anim_mock: AnimDriverMock = null

# =============================================================================
# 节点引用
# =============================================================================
var _eye_hurtbox: Area2D = null
var _hurtbox_main: Area2D = null
var _ground_pound_hitbox: Area2D = null
var _tail_sweep_hitbox: Area2D = null
var _detect_area: Area2D = null
var _light_receiver: Area2D = null

@onready var _spine_sprite: Node = null

# =============================================================================
# 生命周期
# =============================================================================

func _ready() -> void:
	# --- 核心属性（在 super._ready 之前设置）---
	species_id = &"chimera_nun_snake"
	attribute_type = AttributeType.LIGHT
	size_tier = SizeTier.MEDIUM
	max_hp = 5
	weak_hp = 1
	can_be_attacked = true
	has_hp = true

	super._ready()

	# entity_type 已在 ChimeraBase._ready 中设为 CHIMERA
	add_to_group("chimera_nun_snake")
	add_to_group("monster")  # 加入 monster 组，被通用怪物系统识别

	# --- 节点引用缓存 ---
	_eye_hurtbox = get_node_or_null("EyeHurtbox") as Area2D
	_hurtbox_main = get_node_or_null("Hurtbox") as Area2D
	_ground_pound_hitbox = get_node_or_null("GroundPoundHitbox") as Area2D
	_tail_sweep_hitbox = get_node_or_null("TailSweepHitbox") as Area2D
	_detect_area = get_node_or_null("DetectArea") as Area2D
	_light_receiver = get_node_or_null(light_receiver_path) as Area2D

	# --- 初始状态：闭眼（主 Hurtbox 激活，EyeHurtbox 关闭）---
	_set_eye_hurtbox_active(false)
	if _ground_pound_hitbox:
		_ground_pound_hitbox.monitoring = false
	if _tail_sweep_hitbox:
		_tail_sweep_hitbox.monitoring = false

	# --- EventBus 信号连接（MonsterBase 等价）---
	if EventBus:
		EventBus.thunder_burst.connect(_on_thunder_burst)
		EventBus.light_started.connect(_on_light_started)
		EventBus.light_finished.connect(_on_light_finished)
		EventBus.healing_burst.connect(_on_healing_burst)
		EventBus.lightning_flower_release.connect(_on_lightning_flower_release)

	# --- LightReceiver 信号连接 ---
	if _light_receiver:
		_light_receiver.area_entered.connect(_on_light_area_entered)

	# --- Spine / Mock 动画驱动 ---
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
	## 修女蛇 _physics_process：
	## - 不调用 super._physics_process（ChimeraBase 的移动/跟随逻辑由 BT 接管）
	## - 不处理移动和重力（由 BT 叶节点控制）
	## - 只处理：光照计时、mock 动画 tick、weak/stun 倒计时、朝向翻转

	# 光照计数器衰减
	if light_counter > 0.0:
		light_counter -= dt
		light_counter = maxf(light_counter, 0.0)
	_thunder_processed_this_frame = false

	# Mock 驱动需要手动 tick
	if _anim_mock:
		_anim_mock.tick(dt)

	# 虚弱/眩晕倒计时
	if mode == Mode.WEAK:
		_weak_timer -= dt
		if _weak_timer <= 0.0:
			_exit_weak()
	elif mode == Mode.STUN:
		_stun_timer -= dt
		if _stun_timer <= 0.0:
			_exit_stun()

	# Spine sprite 朝向翻转
	if _spine_sprite != null and is_instance_valid(_spine_sprite):
		_spine_sprite.scale.x = absf(_spine_sprite.scale.x) * float(facing)


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
			_set_attack_hitbox_active(true)
		&"atk_hit_off":
			ev_atk_hit_off = true
			atk_hit_window_open = false
			_set_attack_hitbox_active(false)
		&"eye_shoot_spawn":
			ev_eye_shoot_spawn = true
		&"guard_break_enter_done":
			ev_guard_break_enter_done = true
		&"open_to_close_done":
			ev_open_to_close_done = true
		&"close_to_open_done":
			ev_close_to_open_done = true
		&"tail_sweep_transition_done":
			ev_tail_sweep_transition_done = true


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
	## 开启 EyeHurtbox 时，同步禁用主 Hurtbox（两者互斥）
	## 关闭 EyeHurtbox 时，恢复主 Hurtbox（CLOSED_EYE 状态可链条检测）
	eye_hurtbox_enabled = active

	# EyeHurtbox 开关
	if _eye_hurtbox != null:
		_eye_hurtbox.monitoring = active
		_eye_hurtbox.monitorable = active
		var eye_shape := _eye_hurtbox.get_node_or_null("CollisionShape2D") as CollisionShape2D
		if eye_shape:
			eye_shape.disabled = not active

	# 主 Hurtbox：闭眼时激活（可被链条检测），睁眼时关闭（仅 EyeHurtbox 有效）
	if _hurtbox_main != null:
		_hurtbox_main.monitoring = not active
		_hurtbox_main.monitorable = not active
		var main_shape := _hurtbox_main.get_node_or_null("CollisionShape2D") as CollisionShape2D
		if main_shape:
			main_shape.disabled = active


func _set_attack_hitbox_active(active: bool) -> void:
	## 根据当前动画上下文激活正确的攻击判定框
	## GroundPoundHitbox 和 TailSweepHitbox 共享同一个 atk_hit_on/off 事件
	## 由 BT 动作层在使用前确保只激活对应的框
	pass  # 由各 BT Action 节点在开启命中窗口前自行管理对应 Hitbox


func force_close_hit_windows() -> void:
	atk_hit_window_open = false
	if _ground_pound_hitbox:
		_ground_pound_hitbox.monitoring = false
	if _tail_sweep_hitbox:
		_tail_sweep_hitbox.monitoring = false


# =============================================================================
# 光照系统（MonsterBase 等价，手动实现）
# =============================================================================

var _processed_light_sources: Dictionary = {}
var _active_light_sources: Dictionary = {}

func _on_thunder_burst(add_seconds: float) -> void:
	if _thunder_processed_this_frame:
		return
	_thunder_processed_this_frame = true
	light_counter += add_seconds
	light_counter = minf(light_counter, light_counter_max)


func _on_healing_burst(light_energy: float) -> void:
	light_counter += light_energy
	light_counter = minf(light_counter, light_counter_max)


func on_light_exposure(remaining_time: float) -> void:
	light_counter += remaining_time
	light_counter = minf(light_counter, light_counter_max)


func _on_light_started(source_id: int, remaining_time: float, source_light_area: Area2D) -> void:
	if _light_receiver == null or source_light_area == null:
		return
	if not source_light_area.overlaps_area(_light_receiver):
		_active_light_sources[source_id] = {
			"area": source_light_area,
			"total_duration": remaining_time,
			"start_time_ms": Time.get_ticks_msec()
		}
		return
	if _processed_light_sources.has(source_id):
		return
	_processed_light_sources[source_id] = true
	light_counter += remaining_time
	light_counter = minf(light_counter, light_counter_max)


func _on_light_finished(source_id: int) -> void:
	_processed_light_sources.erase(source_id)
	_active_light_sources.erase(source_id)


func _on_light_area_entered(area: Area2D) -> void:
	if area == null:
		return
	for source_id in _active_light_sources.keys():
		var light_data: Dictionary = _active_light_sources[source_id]
		if light_data["area"] == area:
			if _processed_light_sources.has(source_id):
				return
			var remaining: float = _get_current_light_remaining(light_data)
			_processed_light_sources[source_id] = true
			light_counter += remaining
			light_counter = minf(light_counter, light_counter_max)
			break


func _get_current_light_remaining(light_data: Dictionary) -> float:
	var total_duration: float = light_data.get("total_duration", 0.0)
	if total_duration <= 0.0:
		return 0.0
	var start_ms: int = int(light_data.get("start_time_ms", 0))
	var elapsed: float = maxf((Time.get_ticks_msec() - start_ms) / 1000.0, 0.0)
	return maxf(total_duration - elapsed, 0.0)


func _on_lightning_flower_release(source: Node2D) -> void:
	if mode != Mode.CLOSED_EYE:
		return
	if source == null or not is_instance_valid(source):
		return
	if source.global_position.distance_to(global_position) > detect_player_radius * 1.5:
		return
	_enter_guard_break()


# =============================================================================
# 受击规则（伤害矩阵）
# =============================================================================

func _can_break_closed_guard(weapon_id: StringName) -> bool:
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
			if hit.weapon_id == &"chain":
				_flash_once()
				return true
			if not _can_break_closed_guard(hit.weapon_id):
				_play_closed_eye_hit_resist()
				return true
			_enter_guard_break()
			_flash_once()
			return true

		Mode.OPEN_EYE, Mode.GUARD_BREAK:
			## 睁眼系：仅命中 EyeHurtbox 有效（主 Hurtbox 已禁用，故所有到达此处的 apply_hit
			## 均来自 EyeHurtbox 或直接事件（如光花放电），无需额外区分）
			if hit.weapon_id == &"chain":
				return false
			# 光花放电可触发 STUN
			if hit.weapon_id == &"lightning_flower" or hit.weapon_id == &"lightflower":
				_enter_stun()
				_flash_once()
				return true
			# 其余有效武器命中眼球 → 扣 HP
			if hp_locked:
				_flash_once()
				return true
			hp = max(hp - hit.damage, 0)
			_flash_once()
			if hp <= weak_hp and hp > 0 and not weak:
				weak = true
				hp_locked = true
				vanish_fusion_count = 0
				_enter_weak()
			elif hp <= 0 and not hp_locked:
				_on_death()
			return true

		Mode.WEAK, Mode.STUN:
			_flash_once()
			return true

	return false


func _play_closed_eye_hit_resist() -> void:
	if (
		anim_is_playing(&"closed_eye_hit_resist")
		or anim_is_playing(&"ground_pound")
		or anim_is_playing(&"tail_sweep")
		or anim_is_playing(&"tail_sweep_transition")
	):
		return
	_flash_once()
	anim_play(&"closed_eye_hit_resist", false, false)


# =============================================================================
# 锁链交互（覆写 ChimeraBase 默认"可直链"行为，改走 Monster 逻辑）
# =============================================================================

func on_chain_hit(player_ref: Node, slot: int) -> int:
	match mode:
		Mode.WEAK, Mode.STUN:
			if is_occupied_by_other_chain(slot):
				return 0
			_linked_player = player_ref
			_player = player_ref as Node2D
			return 1
		_:
			_flash_once()
			return 0


func on_chain_attached(slot: int) -> void:
	## 链接时（由 player_chain_system 调用）
	# 第一条链连接时禁用 Hurtbox 碰撞层
	if _linked_slots.is_empty():
		if _hurtbox != null:
			_hurtbox_original_layer = _hurtbox.collision_layer
			_hurtbox.collision_layer = 0
	if not _linked_slots.has(slot):
		_linked_slots.append(slot)
	_linked_slot = slot
	# 延长虚弱/眩晕时间
	if mode == Mode.WEAK:
		_weak_timer += 3.0
	elif mode == Mode.STUN:
		_stun_timer += 3.0
	_flash_once()


func on_chain_detached(slot: int) -> void:
	## 链断开时
	_linked_slots.erase(slot)
	if _linked_slots.is_empty():
		_linked_slot = -1
		_linked_player = null
		_player = null
		if _hurtbox != null and _hurtbox_original_layer >= 0:
			_hurtbox.collision_layer = _hurtbox_original_layer
			_hurtbox_original_layer = -1
	else:
		_linked_slot = _linked_slots[0]


# =============================================================================
# 状态切换（供 BT 叶节点调用）
# =============================================================================

func enter_mode(new_mode: int) -> void:
	match new_mode:
		Mode.CLOSED_EYE:
			mode = new_mode
			_set_eye_hurtbox_active(false)
			opening_transition_lock = false
			closing_transition_lock = false
		Mode.OPEN_EYE:
			mode = new_mode
			opening_transition_lock = false
		Mode.GUARD_BREAK:
			_enter_guard_break()
		Mode.WEAK:
			_enter_weak()
		Mode.STUN:
			_enter_stun()


func _enter_guard_break() -> void:
	if mode == Mode.GUARD_BREAK:
		return  # 防止重复进入
	mode = Mode.GUARD_BREAK
	force_close_hit_windows()
	_set_eye_hurtbox_active(true)
	guard_break_end_ms = Time.get_ticks_msec() + int(guard_break_duration_sec * 1000.0)
	velocity = Vector2.ZERO


func _enter_weak() -> void:
	mode = Mode.WEAK
	_weak_timer = weak_duration
	force_close_hit_windows()
	velocity = Vector2.ZERO
	if eye_phase != EyePhase.SOCKETED:
		_force_eye_recall()


func _exit_weak() -> void:
	hp = max_hp
	weak = false
	hp_locked = false
	vanish_fusion_count = 0
	mode = Mode.CLOSED_EYE
	_set_eye_hurtbox_active(false)
	_release_linked_chains()


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
	_release_linked_chains()


func _force_eye_recall() -> void:
	eye_phase = EyePhase.FORCE_RECALL
	if _eye_projectile_instance != null and is_instance_valid(_eye_projectile_instance):
		if _eye_projectile_instance.has_method("force_recall"):
			_eye_projectile_instance.call("force_recall")


func _release_linked_chains() -> void:
	## 释放所有链接的锁链（MonsterBase._release_linked_chains 等价）
	var slots: Array[int] = _linked_slots.duplicate()
	_linked_slots.clear()
	_linked_slot = -1
	var p: Node = _linked_player
	_linked_player = null
	_player = null

	# 恢复 Hurtbox 碰撞层
	if _hurtbox != null and _hurtbox_original_layer >= 0:
		_hurtbox.collision_layer = _hurtbox_original_layer
		_hurtbox_original_layer = -1

	# 通知 Player/ChainSystem 溶解锁链
	if p == null or not is_instance_valid(p):
		return
	for s in slots:
		_force_dissolve_chain_on_player(p, s)


func _force_dissolve_chain_on_player(p: Node, slot: int) -> void:
	if p == null or not is_instance_valid(p):
		return
	if p.has_method("force_dissolve_chain"):
		p.call("force_dissolve_chain", slot)
		return
	var chain_sys: Object = p.get("chain_sys")
	if chain_sys != null and chain_sys.has_method("force_dissolve_chain"):
		chain_sys.call("force_dissolve_chain", slot)


# =============================================================================
# 眼球子弹接口（供 BT 叶节点调用）
# =============================================================================

func spawn_eye_projectile() -> Node2D:
	if eye_projectile_scene == null:
		push_error("[ChimeraNunSnake] eye_projectile_scene 未设置")
		return null
	if _eye_projectile_instance != null and is_instance_valid(_eye_projectile_instance):
		return _eye_projectile_instance
	var proj: Node = (eye_projectile_scene as PackedScene).instantiate()
	var proj2d := proj as Node2D
	if proj2d != null:
		proj2d.global_position = get_eye_socket_world_pos()
		if proj.has_method("setup"):
			proj.call("setup", self)
	get_parent().add_child(proj)
	_eye_projectile_instance = proj2d
	eye_phase = EyePhase.OUTBOUND
	return proj2d


func get_eye_socket_world_pos() -> Vector2:
	if _anim_driver != null:
		var bone_pos: Vector2 = _anim_driver.get_bone_world_position("bone_eye_socket")
		if bone_pos != Vector2.ZERO:
			return bone_pos
	var mark := get_node_or_null("EyeSocketMark") as Node2D
	if mark != null:
		return mark.global_position
	if _eye_hurtbox != null:
		return _eye_hurtbox.global_position
	return global_position + Vector2(0.0, -40.0)


func notify_eye_returned() -> void:
	eye_phase = EyePhase.SOCKETED
	_eye_projectile_instance = null


# =============================================================================
# 感知接口（供 BT 条件节点调用）
# =============================================================================

func get_priority_attack_target() -> Node2D:
	## 与 MonsterBase.get_priority_attack_target 等价
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
		if d < nearest_dist:
			nearest_dist = d
			nearest = n
	return nearest


func get_player() -> Node2D:
	## 优先从 DetectArea 获取，否则从组获取最近目标
	if _detect_area != null:
		for body in _detect_area.get_overlapping_bodies():
			if body.is_in_group(ATTACK_TARGET_GROUP) or body.is_in_group("player"):
				return body as Node2D
		for area in _detect_area.get_overlapping_areas():
			var host: Node = area
			while host != null:
				if host is Node2D and host.is_in_group(ATTACK_TARGET_GROUP):
					return host as Node2D
				host = host.get_parent()
	return get_priority_attack_target()


func get_petrified_player() -> Node2D:
	var players: Array = get_tree().get_nodes_in_group("player")
	for p in players:
		if p.has_method("is_petrified") and p.call("is_petrified"):
			return p as Node2D
	return null


func is_player_in_range(range_px: float) -> bool:
	var player: Node2D = get_player()
	if player == null:
		return false
	return absf(player.global_position.x - global_position.x) <= range_px


func is_player_in_detect_area() -> bool:
	return get_player() != null


# =============================================================================
# 辅助
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
	_anim_mock._durations[&"stiff_attack"] = 0.5
	_anim_mock._durations[&"open_eye_idle"] = 1.0
	_anim_mock._durations[&"shoot_eye_start"] = 0.4
	_anim_mock._durations[&"shoot_eye_loop"] = 1.0
	_anim_mock._durations[&"shoot_eye_end"] = 0.4
	_anim_mock._durations[&"shoot_eye_recall_weak_or_stun"] = 0.4
	_anim_mock._durations[&"open_eye_to_close"] = 0.5
	_anim_mock._durations[&"guard_break_enter"] = 0.4
	_anim_mock._durations[&"guard_break_loop"] = 1.0
	_anim_mock._durations[&"ground_pound"] = 0.6
	_anim_mock._durations[&"tail_sweep_transition"] = 0.4
	_anim_mock._durations[&"tail_sweep"] = 0.5
	_anim_mock._durations[&"weak"] = 0.4
	_anim_mock._durations[&"weak_loop"] = 1.0
	_anim_mock._durations[&"stun"] = 0.4
	_anim_mock._durations[&"stun_loop"] = 1.0
