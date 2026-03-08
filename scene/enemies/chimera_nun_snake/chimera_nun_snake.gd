extends MonsterBase
class_name ChimeraNunSnake

## =============================================================================
## ChimeraNunSnake — 修女蛇（Chimera 类型，按 Monster 攻击型处理）
## =============================================================================
## 顶层状态：CLOSED_EYE / OPEN_EYE / GUARD_BREAK / WEAK / STUN
## 行为由 Beehave 行为树驱动，动画由 AnimDriverSpine 驱动（无 Spine 时 AnimDriverMock）。
## 链条规则走 Monster 逻辑：默认不可链，只有 weak/stunned 可链。
## 蓝图：docs/NUN_SNAKE_CHIMERA_BLUEPRINT_v0.7.md
## =============================================================================

# ===== 顶层状态枚举 =====
enum Mode {
	CLOSED_EYE = 0,
	OPEN_EYE = 1,
	GUARD_BREAK = 2,
	WEAK = 3,
	STUN = 4,
}

# ===== 眼球阶段 =====
enum EyePhase {
	SOCKETED = 0,
	OUTBOUND = 1,
	HOVER = 2,
	RETARGETING = 3,
	RETURNING = 4,
	FORCE_RECALL = 5,
}

# ===== 通用参数 =====
@export var detect_player_radius: float = 240.0
@export var detect_attack_target_radius: float = 240.0
@export var closed_walk_speed: float = 90.0
@export var closed_run_speed: float = 130.0
@export var petrified_target_chase_speed: float = 150.0

# ===== 状态参数 =====
@export var guard_break_duration_sec: float = 0.8
@export var open_eye_idle_timeout: float = 1.2
@export var closed_eye_poll_interval: float = 0.1
@export var weak_eye_recall_check_interval: float = 1.0
@export var nun_snake_weak_duration: float = 2.5
@export var nun_snake_stun_duration: float = 1.2

# ===== 攻击A：stiff_attack =====
@export var stiff_attack_range: float = 80.0
@export var stiff_attack_damage: int = 1
@export var stiff_attack_player_stun_sec: float = 0.5

# ===== 攻击B：shoot_eye =====
@export var eye_projectile_speed: float = 420.0
@export var eye_projectile_hover_sec: float = 0.5
@export var eye_projectile_retarget_count: int = 3
@export var eye_projectile_invincible: bool = true
@export var eye_return_speed: float = 700.0
@export var eye_projectile_max_lifetime_sec: float = 10.0

# ===== 攻击C：ground_pound =====
@export var ground_pound_range: float = 110.0
@export var ground_pound_damage: int = 1

# ===== 攻击D：tail_sweep =====
@export var tail_sweep_range: float = 140.0
@export var tail_sweep_knockback_px: float = 200.0
@export var tail_sweep_execute_petrified: bool = true

# ===== 攻击冷却 =====
@export var attack_cooldown_sec: float = 1.0

# ===== 石化参数（玩家） =====
@export var stone_recover_enabled: bool = true
@export var stone_auto_recover_sec: float = 3.0
@export var stone_forced_death_sec: float = 10.0
@export var stone_hurt_kill: bool = true

# ===== 内部状态（BT 叶节点直接读写） =====
var mode: int = Mode.CLOSED_EYE
var eye_phase: int = EyePhase.SOCKETED

## 攻击冷却结束时间
var _attack_cooldown_end_sec: float = 0.0

## 转场锁：防止 reactive BT 在开眼/关眼过程反复抢占
var opening_transition_lock: bool = false
var closing_transition_lock: bool = false

## guard_break 结束时间
var guard_break_end_sec: float = 0.0

## 眼球子弹实例引用
var eye_projectile_instance: Node2D = null

## 当前感知到的石化玩家引用
var petrified_target_node: Node2D = null

## 闭眼抗性动画保护：防止被无效攻击反复打断
var _hit_resist_playing: bool = false

## 攻击命中窗口
var _atk_hit_window_open: bool = false

## EyeHurtbox 引用
@onready var _eye_hurtbox: Area2D = get_node_or_null("EyeHurtbox") as Area2D

## GroundPoundHitbox 常驻节点
@onready var _ground_pound_hitbox: Area2D = get_node_or_null("GroundPoundHitbox") as Area2D

## TailSweepHitbox
@onready var _tail_sweep_hitbox: Area2D = get_node_or_null("TailSweepHitbox") as Area2D

## StiffAttackHitbox
@onready var _stiff_attack_hitbox: Area2D = get_node_or_null("StiffAttackHitbox") as Area2D

# ===== 动画状态追踪 =====
var _current_anim: StringName = &""
var _current_anim_finished: bool = false
var _current_anim_loop: bool = false
var _current_anim_started_sec: float = -1.0

# Spine 动画驱动
var _anim_driver: AnimDriverSpine = null
var _anim_mock: AnimDriverMock = null
@onready var _spine_sprite: Node = null

# ===== 预加载眼球子弹场景 =====
const EYE_PROJECTILE_SCENE_PATH: String = "res://scene/enemies/chimera_nun_snake/NunSnakeEyeProjectile.tscn"
var _eye_projectile_scene: PackedScene = null

# ===== 破防来源标签 =====
const GUARD_BREAK_SOURCES: Array[StringName] = [
	&"ghost_fist",
	&"chimera_ghost_hand_l",
	&"lightning_flower",
	&"lightflower",
	&"healing_burst",
]

# ===== 生命周期 =====

func _ready() -> void:
	species_id = &"chimera_nun_snake"
	entity_type = EntityType.CHIMERA
	attribute_type = AttributeType.LIGHT
	size_tier = SizeTier.MEDIUM
	max_hp = 5
	weak_hp = 1
	vanish_fusion_required = 1

	super._ready()
	add_to_group("monster")

	# 预加载眼球场景
	if ResourceLoader.exists(EYE_PROJECTILE_SCENE_PATH):
		_eye_projectile_scene = load(EYE_PROJECTILE_SCENE_PATH) as PackedScene

	# 初始化动画驱动
	_spine_sprite = get_node_or_null("SpineSprite")
	if _is_spine_sprite_compatible(_spine_sprite):
		_anim_driver = AnimDriverSpine.new()
		add_child(_anim_driver)
		_anim_driver.setup(_spine_sprite)
		_anim_driver.anim_completed.connect(_on_anim_completed)
		if _spine_sprite.has_signal("animation_event"):
			_spine_sprite.animation_event.connect(_on_spine_animation_event)
	else:
		_anim_mock = AnimDriverMock.new()
		_setup_mock_durations()
		add_child(_anim_mock)
		_anim_mock.anim_completed.connect(_on_anim_completed)

	# 初始状态：闭眼
	_enter_closed_eye()


func _is_spine_sprite_compatible(node: Node) -> bool:
	if node == null:
		return false
	if String(node.get_class()) == "SpineSprite":
		return true
	return node.has_method("get_animation_state")


func _physics_process(dt: float) -> void:
	# 光照系统
	if light_counter > 0.0:
		light_counter -= dt
		light_counter = max(light_counter, 0.0)
	_thunder_processed_this_frame = false

	# Mock 驱动 tick
	if _anim_mock:
		_anim_mock.tick(dt)

	# WEAK 计时
	if mode == Mode.WEAK:
		if weak_stun_t > 0.0:
			weak_stun_t -= dt
			if weak_stun_t <= 0.0:
				weak_stun_t = 0.0
				_restore_from_weak_nun_snake()

	# STUN 计时
	if mode == Mode.STUN:
		if stunned_t > 0.0:
			stunned_t -= dt
			if stunned_t <= 0.0:
				stunned_t = 0.0
				_restore_from_stun_nun_snake()

	# 重力（与 MonsterWalk 同步 1200 px/s²）
	if not is_on_floor():
		velocity.y += dt * 1200.0  # gravity
	else:
		velocity.y = max(velocity.y, 0.0)
	move_and_slide()

	# 不调用 super._physics_process()：
	# MonsterBase 的 weak/stunned_t 系统由我们自己的 mode 系统替代。
	# BeehaveTree 的 tick 由其自身 _physics_process 驱动。


func _do_move(_dt: float) -> void:
	pass


# =============================================================================
# 动画播放接口（供 BT 叶节点统一调用）
# =============================================================================

func anim_play(anim_name: StringName, loop: bool, _interruptible: bool = true) -> void:
	if _current_anim == anim_name and not _current_anim_finished and _current_anim_loop == loop:
		return
	_current_anim = anim_name
	_current_anim_finished = false
	_current_anim_loop = loop
	_current_anim_started_sec = now_sec()
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
	_current_anim_started_sec = -1.0
	if _anim_driver:
		_anim_driver.stop_all()
	elif _anim_mock:
		_anim_mock.stop(0)


func _on_anim_completed(_track: int, anim_name: StringName) -> void:
	if anim_name == _current_anim:
		_current_anim_finished = true


static func now_sec() -> float:
	return Time.get_ticks_msec() / 1000.0


# =============================================================================
# Spine 事件回调
# =============================================================================

func _on_spine_animation_event(a1, a2, a3, a4) -> void:
	var spine_event: Object = null
	for a in [a1, a2, a3, a4]:
		if a is Object and a.has_method("get_data"):
			spine_event = a
			break
	if spine_event == null:
		return
	var event_name: StringName = &""
	var data = spine_event.get_data()
	if data != null and data.has_method("get_event_name"):
		event_name = StringName(data.get_event_name())
	if event_name == &"":
		return

	match event_name:
		&"eye_hurtbox_enable":
			_set_eye_hurtbox_enabled(true)
		&"eye_hurtbox_disable":
			_set_eye_hurtbox_enabled(false)
		&"atk_hit_on":
			_atk_hit_window_open = true
			_enable_current_attack_hitbox(true)
		&"atk_hit_off":
			_atk_hit_window_open = false
			_enable_current_attack_hitbox(false)
		&"eye_shoot_spawn":
			_spawn_eye_projectile()
		&"guard_break_enter_done":
			pass  # BT 通过 anim_is_finished 检测
		&"open_to_close_done":
			closing_transition_lock = false
		&"close_to_open_done":
			opening_transition_lock = false
		&"tail_sweep_transition_done":
			pass  # BT 通过 anim_is_finished 检测


# =============================================================================
# 状态进入辅助
# =============================================================================

func _enter_closed_eye() -> void:
	mode = Mode.CLOSED_EYE
	_set_eye_hurtbox_enabled(false)
	_set_main_hurtbox_defense_config()
	_hit_resist_playing = false
	force_close_all_hitboxes()
	anim_play(&"closed_eye_idle", true)


func _enter_open_eye() -> void:
	mode = Mode.OPEN_EYE
	_set_eye_hurtbox_enabled(true)
	_set_main_hurtbox_open_eye_config()


func _enter_guard_break() -> void:
	mode = Mode.GUARD_BREAK
	_set_eye_hurtbox_enabled(true)
	_set_main_hurtbox_open_eye_config()
	guard_break_end_sec = now_sec() + guard_break_duration_sec
	_hit_resist_playing = false
	force_close_all_hitboxes()
	anim_play(&"guard_break_enter", false)


func _enter_weak() -> void:
	var prev_mode: int = mode
	mode = Mode.WEAK
	hp = max(hp, 1)
	weak = true
	hp_locked = true
	reset_vanish_count()
	weak_stun_t = nun_snake_weak_duration
	force_close_all_hitboxes()
	velocity.x = 0.0

	# 终止攻击链
	_abort_attack_chain()

	# 眼球强制召回
	if eye_phase != EyePhase.SOCKETED:
		eye_phase = EyePhase.FORCE_RECALL
		if eye_projectile_instance != null and is_instance_valid(eye_projectile_instance):
			if eye_projectile_instance.has_method("force_recall"):
				eye_projectile_instance.call("force_recall")
		anim_play(&"shoot_eye_recall_weak_or_stun", false)
	else:
		anim_play(&"weak", false)


func _enter_stun() -> void:
	var prev_mode: int = mode
	mode = Mode.STUN
	stunned_t = nun_snake_stun_duration
	force_close_all_hitboxes()
	velocity.x = 0.0

	_abort_attack_chain()

	if eye_phase != EyePhase.SOCKETED:
		eye_phase = EyePhase.FORCE_RECALL
		if eye_projectile_instance != null and is_instance_valid(eye_projectile_instance):
			if eye_projectile_instance.has_method("force_recall"):
				eye_projectile_instance.call("force_recall")
		anim_play(&"shoot_eye_recall_weak_or_stun", false)
	else:
		anim_play(&"stun", false)


func _restore_from_weak_nun_snake() -> void:
	hp = max_hp
	weak = false
	hp_locked = false
	weak_stun_t = 0.0
	reset_vanish_count()
	_release_linked_chains()
	_enter_closed_eye()


func _restore_from_stun_nun_snake() -> void:
	stunned_t = 0.0
	_release_linked_chains()
	_enter_closed_eye()


func _abort_attack_chain() -> void:
	opening_transition_lock = false
	closing_transition_lock = false
	_hit_resist_playing = false


# =============================================================================
# Hurtbox 配置切换
# =============================================================================

func _set_eye_hurtbox_enabled(enabled: bool) -> void:
	if _eye_hurtbox == null:
		return
	for child in _eye_hurtbox.get_children():
		var cs: CollisionShape2D = child as CollisionShape2D
		if cs != null:
			cs.set_deferred("disabled", not enabled)


func _set_main_hurtbox_defense_config() -> void:
	# 闭眼：主 Hurtbox 存在但不参与有效伤害
	# collision_layer 保持，用于链条溶解检测
	pass


func _set_main_hurtbox_open_eye_config() -> void:
	# 睁眼：主 Hurtbox 无效，只有 EyeHurtbox 有效
	pass


# =============================================================================
# 攻击 Hitbox 管理
# =============================================================================

func _enable_current_attack_hitbox(enabled: bool) -> void:
	# 根据当前动画决定启用哪个 hitbox
	match _current_anim:
		&"stiff_attack":
			_set_hitbox_enabled(_stiff_attack_hitbox, enabled)
		&"ground_pound":
			_set_hitbox_enabled(_ground_pound_hitbox, enabled)
		&"tail_sweep":
			_set_hitbox_enabled(_tail_sweep_hitbox, enabled)


func _set_hitbox_enabled(hitbox: Area2D, enabled: bool) -> void:
	if hitbox == null:
		return
	hitbox.set_deferred("monitoring", enabled)
	hitbox.set_deferred("monitorable", enabled)
	for child in hitbox.get_children():
		var cs: CollisionShape2D = child as CollisionShape2D
		if cs != null:
			cs.set_deferred("disabled", not enabled)


func force_close_all_hitboxes() -> void:
	_atk_hit_window_open = false
	_set_hitbox_enabled(_stiff_attack_hitbox, false)
	_set_hitbox_enabled(_ground_pound_hitbox, false)
	_set_hitbox_enabled(_tail_sweep_hitbox, false)


# =============================================================================
# 眼球子弹生成
# =============================================================================

func _spawn_eye_projectile() -> void:
	if _eye_projectile_scene == null:
		push_warning("[ChimeraNunSnake] Eye projectile scene not loaded")
		return
	if eye_projectile_instance != null and is_instance_valid(eye_projectile_instance):
		return  # 已有眼球在场

	var target: Node2D = get_priority_attack_target()
	if target == null:
		return

	var bullet: Node2D = (_eye_projectile_scene as PackedScene).instantiate() as Node2D
	bullet.name = "NunSnakeEyeBullet"

	# 出生点：bone_eye_socket 或默认自身位置
	var spawn_pos: Vector2 = global_position
	if _anim_driver != null:
		var bone_pos: Vector2 = _anim_driver.get_bone_world_position("bone_eye_socket")
		if bone_pos != Vector2.ZERO:
			spawn_pos = bone_pos

	bullet.global_position = spawn_pos

	if bullet.has_method("setup"):
		bullet.call("setup", target, self, eye_projectile_speed, eye_projectile_hover_sec,
			eye_projectile_retarget_count, eye_return_speed, eye_projectile_max_lifetime_sec)

	get_parent().add_child(bullet)
	eye_projectile_instance = bullet
	eye_phase = EyePhase.OUTBOUND


func on_eye_projectile_returned() -> void:
	## 由眼球子弹回归后调用
	eye_phase = EyePhase.SOCKETED
	eye_projectile_instance = null


func on_eye_projectile_destroyed() -> void:
	## 由眼球子弹销毁时调用（超时兜底等）
	eye_phase = EyePhase.SOCKETED
	eye_projectile_instance = null


func get_eye_socket_position() -> Vector2:
	## 眼球返航目标位置
	if _anim_driver != null:
		var bone_pos: Vector2 = _anim_driver.get_bone_world_position("bone_eye_socket")
		if bone_pos != Vector2.ZERO:
			return bone_pos
	return global_position


# =============================================================================
# 受击规则（核心：按 mode 判定，蓝图第 7 节）
# =============================================================================

func apply_hit(hit: HitData) -> bool:
	if hit == null:
		return false
	if not has_hp or hp <= 0:
		return false

	match mode:
		Mode.CLOSED_EYE:
			return _apply_hit_closed_eye(hit)
		Mode.OPEN_EYE:
			return _apply_hit_open_eye(hit)
		Mode.GUARD_BREAK:
			return _apply_hit_open_eye(hit)  # 同 OPEN_EYE 规则
		Mode.WEAK, Mode.STUN:
			return _apply_hit_weak_stun(hit)

	return false


func _apply_hit_closed_eye(hit: HitData) -> bool:
	# 检查是否为破防来源
	if _is_guard_break_source(hit.weapon_id):
		_enter_guard_break()
		_flash_once()
		return true

	# 普通攻击无效 —— 播放抗性反馈（防止重复刷新）
	if not _hit_resist_playing:
		_hit_resist_playing = true
		anim_play(&"closed_eye_hit_resist", false)
	_flash_once()
	return false


func _apply_hit_open_eye(hit: HitData) -> bool:
	# 仅 EyeHurtbox 命中有效（此处由 EyeHurtbox 路由调用）
	# 如果是通过主 Hurtbox 进来的，无效
	if hp_locked:
		_flash_once()
		return true

	hp = max(hp - hit.damage, 0)
	_flash_once()

	if hp <= weak_hp:
		_enter_weak()
		return true

	# 光花/治愈爆炸可触发 STUN
	if _is_stun_source(hit.weapon_id):
		_enter_stun()
		return true

	_update_weak_state()
	return true


func _apply_hit_weak_stun(hit: HitData) -> bool:
	# WEAK/STUN：hp_locked，只闪白
	if hp_locked:
		_flash_once()
		return true
	_flash_once()
	return true


func apply_hit_eye_hurtbox(hit: HitData) -> bool:
	## 由 EyeHurtbox 专用脚本调用，路由到睁眼受击逻辑
	if mode != Mode.OPEN_EYE and mode != Mode.GUARD_BREAK:
		return false  # 闭眼时 EyeHurtbox 应该被禁用
	return _apply_hit_open_eye(hit)


func _is_guard_break_source(weapon_id: StringName) -> bool:
	return weapon_id in GUARD_BREAK_SOURCES


func _is_stun_source(weapon_id: StringName) -> bool:
	return weapon_id == &"lightning_flower" or weapon_id == &"lightflower" or weapon_id == &"healing_burst"


# =============================================================================
# 锁链交互（覆写：Chimera 类型但走 Monster 链条逻辑）
# =============================================================================

func on_chain_hit(_player: Node, _slot: int) -> int:
	# CLOSED_EYE：chain 只溶解，不建链，不扣血
	if mode == Mode.CLOSED_EYE:
		_flash_once()
		return 0

	# OPEN_EYE / GUARD_BREAK：chain 只对 EyeHurtbox 有效，主体无效
	if mode == Mode.OPEN_EYE or mode == Mode.GUARD_BREAK:
		_flash_once()
		return 0

	# WEAK / STUN：可链接
	if mode == Mode.WEAK or mode == Mode.STUN:
		_linked_player = _player
		return 1

	return 0


func on_chain_attached(slot: int) -> void:
	if _linked_slots.is_empty():
		if _hurtbox != null:
			_hurtbox_original_layer = _hurtbox.collision_layer
			_hurtbox.collision_layer = 0  # 链接后禁用受击判定
	if not _linked_slots.has(slot):
		_linked_slots.append(slot)
	_linked_slot = slot

	# 延长 weak/stun 时间
	if mode == Mode.WEAK:
		weak_stun_t += weak_stun_extend_time
	elif mode == Mode.STUN:
		stunned_t += weak_stun_extend_time
	_flash_once()


# =============================================================================
# 治愈精灵爆炸反应
# =============================================================================

func apply_healing_burst_stun() -> void:
	if mode == Mode.CLOSED_EYE:
		_enter_guard_break()
	elif mode == Mode.OPEN_EYE or mode == Mode.GUARD_BREAK:
		_enter_stun()


func on_light_exposure(remaining_time: float) -> void:
	super.on_light_exposure(remaining_time)
	if remaining_time <= 0.0:
		return
	if mode == Mode.WEAK or mode == Mode.STUN:
		return
	if mode == Mode.CLOSED_EYE:
		_enter_guard_break()
	elif mode == Mode.OPEN_EYE or mode == Mode.GUARD_BREAK:
		_enter_stun()


# =============================================================================
# 感知辅助
# =============================================================================

func detect_player_in_range(radius: float) -> Node2D:
	var target: Node2D = get_priority_attack_target()
	if target == null:
		return null
	if global_position.distance_to(target.global_position) <= radius:
		return target
	return null


func detect_petrified_player() -> Node2D:
	## 检测场内是否有石化玩家
	var players: Array[Node] = get_tree().get_nodes_in_group("player")
	for p in players:
		if not is_instance_valid(p):
			continue
		# 检查玩家是否处于 PETRIFIED 状态
		if p.has_method("is_petrified") and p.call("is_petrified"):
			return p as Node2D
	return null


func start_attack_cooldown() -> void:
	_attack_cooldown_end_sec = now_sec() + attack_cooldown_sec


func is_attack_on_cooldown() -> bool:
	return now_sec() < _attack_cooldown_end_sec


func is_player_in_range(target: Node2D, range_px: float) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	return global_position.distance_to(target.global_position) <= range_px


func face_toward(target: Node2D) -> void:
	if target == null or not is_instance_valid(target):
		return
	var dir_x: float = target.global_position.x - global_position.x
	if dir_x > 0.0:
		if _spine_sprite != null:
			_spine_sprite.scale.x = abs(_spine_sprite.scale.x)
	elif dir_x < 0.0:
		if _spine_sprite != null:
			_spine_sprite.scale.x = -abs(_spine_sprite.scale.x)


# =============================================================================
# 攻击判定回调（hitbox body_entered）
# =============================================================================

func _on_stiff_attack_hitbox_body_entered(body: Node2D) -> void:
	if not _atk_hit_window_open:
		return
	if _current_anim != &"stiff_attack":
		return
	if body.has_method("apply_damage"):
		body.call("apply_damage", stiff_attack_damage, global_position)
	if body.has_method("apply_stun"):
		body.call("apply_stun", stiff_attack_player_stun_sec)


func _on_ground_pound_hitbox_body_entered(body: Node2D) -> void:
	if not _atk_hit_window_open:
		return
	if _current_anim != &"ground_pound":
		return
	if body.has_method("apply_damage"):
		body.call("apply_damage", ground_pound_damage, global_position)


func _on_tail_sweep_hitbox_body_entered(body: Node2D) -> void:
	if not _atk_hit_window_open:
		return
	if _current_anim != &"tail_sweep":
		return

	# 石化玩家：即死处决
	if tail_sweep_execute_petrified and body.has_method("is_petrified"):
		if body.call("is_petrified"):
			if body.has_method("execute_petrified_death"):
				body.call("execute_petrified_death")
			return

	# 非石化玩家：击退
	if body.has_method("apply_damage"):
		body.call("apply_damage", 1, global_position)
	if body is CharacterBody2D:
		var kb_dir: float = sign(body.global_position.x - global_position.x)
		if kb_dir == 0.0:
			kb_dir = 1.0
		body.velocity.x = kb_dir * tail_sweep_knockback_px * 5.0  # 冲量


# =============================================================================
# Mock 驱动初始化
# =============================================================================

func _setup_mock_durations() -> void:
	_anim_mock._durations[&"closed_eye_idle"] = 1.0
	_anim_mock._durations[&"closed_eye_walk"] = 0.8
	_anim_mock._durations[&"closed_eye_run"] = 0.6
	_anim_mock._durations[&"closed_eye_hit_resist"] = 0.4
	_anim_mock._durations[&"close_to_open"] = 0.6
	_anim_mock._durations[&"stiff_attack"] = 0.5
	_anim_mock._durations[&"open_eye_idle"] = 1.0
	_anim_mock._durations[&"shoot_eye_start"] = 0.4
	_anim_mock._durations[&"shoot_eye_loop"] = 1.0
	_anim_mock._durations[&"shoot_eye_end"] = 0.4
	_anim_mock._durations[&"shoot_eye_recall_weak_or_stun"] = 0.6
	_anim_mock._durations[&"open_eye_to_close"] = 0.5
	_anim_mock._durations[&"guard_break_enter"] = 0.4
	_anim_mock._durations[&"guard_break_loop"] = 1.0
	_anim_mock._durations[&"ground_pound"] = 0.6
	_anim_mock._durations[&"tail_sweep_transition"] = 0.3
	_anim_mock._durations[&"tail_sweep"] = 0.5
	_anim_mock._durations[&"weak"] = 0.5
	_anim_mock._durations[&"weak_loop"] = 1.0
	_anim_mock._durations[&"stun"] = 0.4
	_anim_mock._durations[&"stun_loop"] = 1.0
