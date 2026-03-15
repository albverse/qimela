extends MonsterBase
class_name BossGhostWitch

## =============================================================================
## BossGhostWitch - 幽灵魔女 Boss（全三阶段）
## =============================================================================
## Phase 1: 石像形态 — 投掷婴儿石像、开场攻击、缓慢移动
## Phase 2: 祈祷形态 — 镰刀斩、飞天砸落、亡灵气流、幽灵拔河
## Phase 3: 无头骑士 — 冲刺、踢人、三连斩、扔镰刀、禁锢、召唤幽灵
## 行为由 Beehave 行为树驱动，动画由 AnimDriverSpine 驱动。
## =============================================================================

# ═══════════════════════════════════════
# 阶段枚举
# ═══════════════════════════════════════
enum Phase { PHASE1 = 1, PHASE2 = 2, PHASE3 = 3 }
enum BabyState { IN_HUG, THROWN, EXPLODED, REPAIRING, DASHING, POST_DASH_WAIT, WINDING_UP, RETURNING, HALO }

# ═══════════════════════════════════════
# 导出参数（Inspector 可调）
# ═══════════════════════════════════════
# -- HP --
@export var phase2_hp_threshold: int = 20
@export var phase3_hp_threshold: int = 10

# -- Phase 1 参数 --
@export var detect_range_px: float = 500.0
@export var slow_move_speed: float = 30.0
@export var baby_throw_speed: float = 600.0
@export var baby_explosion_radius: float = 80.0
@export var baby_repair_duration: float = 2.0
@export var baby_dash_speed: float = 400.0
@export var baby_post_dash_wait: float = 0.7
@export var baby_return_speed: float = 500.0
@export var start_attack_loop_duration: float = 4.0

# -- Phase 2 参数 --
@export var scythe_slash_cooldown: float = 1.0
@export var tombstone_drop_cooldown: float = 3.0
@export var undead_wind_cooldown: float = 15.0
@export var ghost_tug_cooldown: float = 5.0
@export var ghost_tug_pull_speed: float = 400.0
@export var tombstone_offset_y: float = 400.0
@export var tombstone_offset_x_range: float = 70.0
@export var tombstone_hover_duration: float = 0.5
@export var tombstone_fall_duration: float = 0.5
@export var tombstone_stagger_duration: float = 1.0
@export var undead_wind_spawn_duration: float = 7.0
@export var undead_wind_total_count: int = 10
@export var ghost_bomb_interval: float = 5.0
@export var ghost_bomb_max_count: int = 3
@export var ghost_bomb_light_energy: float = 5.0

# -- Phase 3 参数 --
@export var p3_move_speed: float = 120.0
@export var p3_run_speed: float = 250.0
@export var p3_dash_cooldown: float = 10.0
@export var p3_dash_charge_time: float = 1.0
@export var p3_dash_speed: float = 800.0
@export var p3_kick_cooldown: float = 1.0
@export var p3_kick_knockback_px: float = 300.0
@export var p3_combo_cooldown: float = 1.0
@export var p3_combo_duration: float = 3.0
@export var p3_imprison_cooldown: float = 10.0
@export var p3_imprison_escape_time: float = 0.5
@export var p3_imprison_stun_time: float = 3.0
@export var p3_scythe_track_interval: float = 1.0
@export var p3_scythe_track_count: int = 3
@export var p3_scythe_fly_speed: float = 300.0
@export var p3_scythe_return_speed: float = 500.0
@export var p3_summon_cooldown: float = 8.0
@export var p3_summon_wave_count: int = 3
@export var p3_summon_circle_count: int = 3
@export var p3_run_slash_overshoot_px: float = 200.0

# ═══════════════════════════════════════
# 运行时状态
# ═══════════════════════════════════════
var current_phase: int = Phase.PHASE1
var baby_state: int = BabyState.IN_HUG
var _phase_transitioning: bool = false
var _battle_started: bool = false
var _baby_realhurtbox_active: bool = false
var _baby_dash_go_triggered: bool = false

# Phase 3 专用状态
var _scythe_in_hand: bool = true
var _scythe_instance: Node2D = null
var _scythe_recall_requested: bool = false
var _hell_hand_instance: Node2D = null
var _player_imprisoned: bool = false

# 攻击窗口标记（Spine 事件驱动）
var _atk_hit_window_open: bool = false

# ═══════════════════════════════════════
# 动画状态追踪
# ═══════════════════════════════════════
var _current_anim: StringName = &""
var _current_anim_finished: bool = false
var _current_anim_loop: bool = false

# ═══════════════════════════════════════
# 子节点引用
# ═══════════════════════════════════════
@onready var _spine_sprite: Node = $SpineSprite
@onready var _baby_statue: Node2D = $BabyStatue
@onready var _baby_spine: Node = $BabyStatue/SpineSprite
@onready var _body_box: Area2D = $BodyBox
@onready var _real_hurtbox: Area2D = $RealHurtbox
@onready var _baby_real_hurtbox: Area2D = $BabyStatue/BabyRealHurtbox
@onready var _baby_body_box: Area2D = $BabyStatue/BabyBodyBox
@onready var _baby_attack_area: Area2D = $BabyStatue/BabyAttackArea
@onready var _baby_explosion_area: Area2D = $BabyStatue/BabyExplosionArea
@onready var _baby_detect_area: Area2D = $BabyStatue/BabyDetectArea
@onready var _scythe_detect_area: Area2D = $ScytheDetectArea
@onready var _ground_hitbox: Area2D = $GroundHitbox
@onready var _mark_hug: Marker2D = $Mark2D_Hug
@onready var _mark_hale: Marker2D = $Mark2D_Hale
# Phase 3 追加
@onready var _kick_hitbox: Area2D = $KickHitbox
@onready var _attack1_area: Area2D = $Attack1Area
@onready var _attack2_area: Area2D = $Attack2Area
@onready var _attack3_area: Area2D = $Attack3Area
@onready var _run_slash_hitbox: Area2D = $RunSlashHitbox

# 预加载子实例场景
var _ghost_tug_scene: PackedScene = preload("res://scene/enemies/boss_ghost_witch/GhostTug.tscn")
var _ghost_bomb_scene: PackedScene = preload("res://scene/enemies/boss_ghost_witch/GhostBomb.tscn")
var _ghost_wraith_scene: PackedScene = preload("res://scene/enemies/boss_ghost_witch/GhostWraith.tscn")
var _ghost_elite_scene: PackedScene = preload("res://scene/enemies/boss_ghost_witch/GhostElite.tscn")
var _witch_scythe_scene: PackedScene = preload("res://scene/enemies/boss_ghost_witch/WitchScythe.tscn")
var _hell_hand_scene: PackedScene = preload("res://scene/enemies/boss_ghost_witch/HellHand.tscn")
var _ghost_summon_scene: PackedScene = preload("res://scene/enemies/boss_ghost_witch/GhostSummon.tscn")

# 动画驱动
var _anim_driver: AnimDriverSpine = null
var _anim_mock: AnimDriverMock = null
var _baby_anim_driver: AnimDriverSpine = null
var _baby_anim_mock: AnimDriverMock = null

# 婴儿动画状态追踪
var _baby_current_anim: StringName = &""
var _baby_current_anim_finished: bool = false
var _baby_current_anim_loop: bool = false

# Phase 1→2 过渡内部状态
var _transition_step: int = 0
var _transition_baby_at_hale: bool = false

# ═══════════════════════════════════════
# 生命周期
# ═══════════════════════════════════════

func _ready() -> void:
	species_id = &"boss_ghost_witch"
	entity_type = EntityType.MONSTER
	attribute_type = AttributeType.NORMAL
	size_tier = SizeTier.LARGE
	max_hp = 30
	hp = 30
	weak_hp = 0
	vanish_fusion_required = 0

	super._ready()
	add_to_group("boss")

	_setup_anim_drivers()
	_enter_phase1()
	_disable_all_hitboxes()


func _setup_anim_drivers() -> void:
	# 魔女主 SpineSprite
	if _is_spine_compatible(_spine_sprite):
		_anim_driver = AnimDriverSpine.new()
		add_child(_anim_driver)
		_anim_driver.setup(_spine_sprite)
		_anim_driver.anim_completed.connect(_on_anim_completed)
		if _spine_sprite.has_signal("animation_event"):
			_spine_sprite.animation_event.connect(_on_spine_animation_event)
	else:
		_anim_mock = AnimDriverMock.new()
		_setup_mock_durations(_anim_mock)
		add_child(_anim_mock)
		_anim_mock.anim_completed.connect(_on_anim_completed)

	# 婴儿石像 SpineSprite
	if _is_spine_compatible(_baby_spine):
		_baby_anim_driver = AnimDriverSpine.new()
		add_child(_baby_anim_driver)
		_baby_anim_driver.setup(_baby_spine)
		_baby_anim_driver.anim_completed.connect(_on_baby_anim_completed)
		if _baby_spine.has_signal("animation_event"):
			_baby_spine.animation_event.connect(_on_baby_spine_event)
	else:
		_baby_anim_mock = AnimDriverMock.new()
		_setup_baby_mock_durations(_baby_anim_mock)
		add_child(_baby_anim_mock)
		_baby_anim_mock.anim_completed.connect(_on_baby_anim_completed)


func _is_spine_compatible(node: Node) -> bool:
	if node == null:
		return false
	if String(node.get_class()) == "SpineSprite":
		return true
	return node.has_method("get_animation_state")


func _setup_mock_durations(mock: AnimDriverMock) -> void:
	mock._durations = {
		# Phase 1
		&"phase1/idle": 1.0,
		&"phase1/idle_no_baby": 1.0,
		&"phase1/walk": 0.8,
		&"phase1/start_attack": 1.0,
		&"phase1/start_attack_loop": 1.0,
		&"phase1/start_attack_exter": 0.8,
		&"phase1/throw": 0.8,
		&"phase1/catch_baby": 0.6,
		&"phase1/hurt": 0.3,
		&"phase1/phase1_to_phase2": 2.0,
		# Phase 2
		&"phase2/idle": 1.0,
		&"phase2/walk": 0.8,
		&"phase2/scythe_slash": 0.8,
		&"phase2/ghost_tug_cast": 0.8,
		&"phase2/ghost_tug_loop": 1.0,
		&"phase2/tombstone_cast": 0.8,
		&"phase2/tombstone_appear": 0.5,
		&"phase2/tombstone_hover": 1.0,
		&"phase2/tombstone_throw": 0.5,
		&"phase2/tombstone_fall": 1.0,
		&"phase2/tombstone_land": 0.5,
		&"phase2/undead_wind_cast": 0.8,
		&"phase2/undead_wind_loop": 1.0,
		&"phase2/undead_wind_end": 0.8,
		&"phase2/phase2_to_phase3": 2.0,
		# Phase 3
		&"phase3/idle": 1.0,
		&"phase3/idle_no_scythe": 1.0,
		&"phase3/walk": 0.8,
		&"phase3/dash_charge": 1.0,
		&"phase3/dash": 1.0,
		&"phase3/dash_brake": 0.5,
		&"phase3/kick": 0.6,
		&"phase3/throw_scythe": 0.8,
		&"phase3/catch_scythe": 0.6,
		&"phase3/imprison": 0.8,
		&"phase3/run_slash": 1.0,
		&"phase3/combo1": 0.6,
		&"phase3/combo2": 0.6,
		&"phase3/combo3": 0.6,
		&"phase3/summon": 1.5,
		&"phase3/summon_loop": 1.0,
		&"phase3/death": 2.0,
		&"phase3/death_loop": 1.0,
	}


func _setup_baby_mock_durations(mock: AnimDriverMock) -> void:
	mock._durations = {
		&"baby/spin": 0.5,
		&"baby/explode": 1.0,
		&"baby/repair": 2.0,
		&"baby/dash": 0.8,
		&"baby/dash_loop": 0.5,
		&"baby/idle": 1.0,
		&"baby/wind_up": 0.6,
		&"baby/return": 0.5,
		&"baby/phase1_to_phase2": 1.5,
	}


# ═══════════════════════════════════════
# _physics_process
# ═══════════════════════════════════════

func _physics_process(dt: float) -> void:
	# 光照系统（保持基类兼容）
	if light_counter > 0.0:
		light_counter -= dt
		light_counter = max(light_counter, 0.0)
	_thunder_processed_this_frame = false

	# Mock 驱动需要手动 tick
	if _anim_mock:
		_anim_mock.tick(dt)
	if _baby_anim_mock:
		_baby_anim_mock.tick(dt)

	# 骨骼跟随
	_sync_hurtboxes()

	# 婴儿石像位置管理
	if current_phase == Phase.PHASE1 and baby_state == BabyState.IN_HUG:
		_baby_statue.global_position = _mark_hug.global_position

	# 婴儿飞行 tick（投掷中）
	if current_phase == Phase.PHASE1 and baby_state == BabyState.THROWN:
		_tick_baby_flight(dt)

	# Phase 过渡 tick
	if _phase_transitioning:
		_tick_phase_transition(dt)

	# 重力
	if not is_on_floor():
		velocity.y += dt * 1200.0
	else:
		velocity.y = max(velocity.y, 0.0)
	move_and_slide()

	# 朝向同步
	_sync_facing_to_sprite()

	# 不调用 super._physics_process()
	# BeehaveTree 由其自身 _physics_process 驱动


func _do_move(_dt: float) -> void:
	pass


# ═══════════════════════════════════════
# 动画播放接口（供 BT 叶节点统一调用）
# ═══════════════════════════════════════

func anim_play(anim_name: StringName, loop: bool) -> void:
	if _current_anim == anim_name and not _current_anim_finished and _current_anim_loop == loop:
		return
	_current_anim = anim_name
	_current_anim_finished = false
	_current_anim_loop = loop
	if _anim_driver:
		_anim_driver.play(0, anim_name, loop, AnimDriverSpine.PlayMode.REPLACE_TRACK)
	elif _anim_mock:
		_anim_mock.play(0, anim_name, loop)


func anim_is_finished(anim_name: StringName) -> bool:
	return _current_anim == anim_name and _current_anim_finished


func anim_is_playing(anim_name: StringName) -> bool:
	return _current_anim == anim_name and not _current_anim_finished


func baby_anim_play(anim_name: StringName, loop: bool) -> void:
	if _baby_current_anim == anim_name and not _baby_current_anim_finished and _baby_current_anim_loop == loop:
		return
	_baby_current_anim = anim_name
	_baby_current_anim_finished = false
	_baby_current_anim_loop = loop
	if _baby_anim_driver:
		_baby_anim_driver.play(0, anim_name, loop, AnimDriverSpine.PlayMode.REPLACE_TRACK)
	elif _baby_anim_mock:
		_baby_anim_mock.play(0, anim_name, loop)


func baby_anim_is_finished(anim_name: StringName) -> bool:
	return _baby_current_anim == anim_name and _baby_current_anim_finished


# ═══════════════════════════════════════
# 动画回调
# ═══════════════════════════════════════

func _on_anim_completed(_track: int, anim_name: StringName) -> void:
	if anim_name == _current_anim:
		_current_anim_finished = true
	# 死亡动画完成 → 切到死亡循环
	if anim_name == &"phase3/death":
		anim_play(&"phase3/death_loop", true)


func _on_baby_anim_completed(_track: int, anim_name: StringName) -> void:
	if anim_name == _baby_current_anim:
		_baby_current_anim_finished = true


# ═══════════════════════════════════════
# Spine 动画事件处理（魔女主体）
# ═══════════════════════════════════════

func _on_spine_animation_event(a1: Variant, a2: Variant, a3: Variant, a4: Variant) -> void:
	var event_name: StringName = _extract_event_name(a1, a2, a3, a4)
	if event_name == &"":
		return

	match event_name:
		# Phase 1
		&"start_attack_hitbox_on":
			_set_hitbox_enabled(_scythe_detect_area, true)
			_atk_hit_window_open = true
		&"start_attack_hitbox_off":
			_set_hitbox_enabled(_scythe_detect_area, false)
			_atk_hit_window_open = false
		&"battle_start":
			_battle_started = true
		&"baby_release":
			_on_baby_release()
		&"baby_return":
			baby_state = BabyState.IN_HUG
		# Phase 2
		&"scythe_hitbox_on":
			_set_hitbox_enabled(_scythe_detect_area, true)
			_atk_hit_window_open = true
		&"scythe_hitbox_off":
			_set_hitbox_enabled(_scythe_detect_area, false)
			_atk_hit_window_open = false
		&"ground_hitbox_on":
			_set_hitbox_enabled(_ground_hitbox, true)
		&"ground_hitbox_off":
			_set_hitbox_enabled(_ground_hitbox, false)
		&"realhurtbox_off":
			_set_realhurtbox_enabled(false)
		&"realhurtbox_on":
			_set_realhurtbox_enabled(true)
		&"phase2_ready":
			_finish_phase_transition()
		&"phase3_ready":
			_finish_phase_transition()
		# Phase 3
		&"kick_hitbox_on":
			_set_hitbox_enabled(_kick_hitbox, true)
			_atk_hit_window_open = true
		&"kick_hitbox_off":
			_set_hitbox_enabled(_kick_hitbox, false)
			_atk_hit_window_open = false
		&"dash_hitbox_on":
			_set_hitbox_enabled(_scythe_detect_area, true)
			_atk_hit_window_open = true
		&"dash_hitbox_off":
			_set_hitbox_enabled(_scythe_detect_area, false)
			_atk_hit_window_open = false
		&"slash_hitbox_on":
			_set_hitbox_enabled(_run_slash_hitbox, true)
			_atk_hit_window_open = true
		&"slash_hitbox_off":
			_set_hitbox_enabled(_run_slash_hitbox, false)
			_atk_hit_window_open = false
		&"combo1_hitbox_on":
			_set_hitbox_enabled(_attack1_area, true)
			_atk_hit_window_open = true
		&"combo1_hitbox_off":
			_set_hitbox_enabled(_attack1_area, false)
			_atk_hit_window_open = false
		&"combo2_hitbox_on":
			_set_hitbox_enabled(_attack2_area, true)
			_atk_hit_window_open = true
		&"combo2_hitbox_off":
			_set_hitbox_enabled(_attack2_area, false)
			_atk_hit_window_open = false
		&"combo3_hitbox_on":
			_set_hitbox_enabled(_attack3_area, true)
			_atk_hit_window_open = true
		&"combo3_hitbox_off":
			_set_hitbox_enabled(_attack3_area, false)
			_atk_hit_window_open = false
		&"death_finished":
			anim_play(&"phase3/death_loop", true)


# ═══════════════════════════════════════
# Spine 动画事件处理（婴儿石像）
# ═══════════════════════════════════════

func _on_baby_spine_event(a1: Variant, a2: Variant, a3: Variant, a4: Variant) -> void:
	var event_name: StringName = _extract_event_name(a1, a2, a3, a4)
	if event_name == &"":
		return

	match event_name:
		&"explode_hitbox_on":
			_set_hitbox_enabled(_baby_explosion_area, true)
		&"explode_hitbox_off":
			_set_hitbox_enabled(_baby_explosion_area, false)
		&"realhurtbox_on":
			_set_baby_realhurtbox(true)
		&"realhurtbox_off":
			_set_baby_realhurtbox(false)
		&"dash_go":
			_baby_dash_go_triggered = true
			_set_hitbox_enabled(_baby_attack_area, true)
		&"dash_hitbox_on":
			_set_hitbox_enabled(_baby_attack_area, true)
		&"become_halo":
			_on_baby_become_halo()


# ═══════════════════════════════════════
# 事件名提取工具
# ═══════════════════════════════════════

func _extract_event_name(a1: Variant, a2: Variant, a3: Variant, a4: Variant) -> StringName:
	for a in [a1, a2, a3, a4]:
		if a is Object and a.has_method("get_data"):
			var data: Variant = a.get_data()
			if data != null and data is Object and data.has_method("get_event_name"):
				return StringName(data.get_event_name())
			if data != null and data is Object and data.has_method("get_name"):
				return StringName(data.get_name())
		# 有些版本直接传事件名
		if a is StringName:
			return a
		if a is String and a != "":
			return StringName(a)
	return &""


# ═══════════════════════════════════════
# HP / 伤害系统
# ═══════════════════════════════════════

func apply_hit(hit: HitData) -> bool:
	if hit == null:
		return false
	if hit.weapon_id != &"ghost_fist":
		_flash_once()
		return false
	apply_real_damage(hit.damage)
	return true


func on_chain_hit(_player: Node, _slot: int) -> int:
	_flash_once()
	return 0


func apply_real_damage(amount: int) -> void:
	if hp_locked:
		_flash_once()
		return
	hp = max(hp - amount, 0)
	_flash_once()

	# Phase 3 扔镰刀期间被打 → 触发镰刀回航
	if current_phase == Phase.PHASE3 and not _scythe_in_hand:
		_scythe_recall_requested = true

	# 阶段切换检查
	if current_phase == Phase.PHASE1 and hp <= phase2_hp_threshold:
		_begin_phase_transition(Phase.PHASE2)
	elif current_phase == Phase.PHASE2 and hp <= phase3_hp_threshold:
		_begin_phase_transition(Phase.PHASE3)
	elif hp <= 0:
		_begin_death()


# ═══════════════════════════════════════
# RealHurtbox / BabyRealHurtbox 信号
# ═══════════════════════════════════════

func _enter_phase1() -> void:
	current_phase = Phase.PHASE1
	baby_state = BabyState.IN_HUG
	_battle_started = false
	# 连接 hurtbox 信号
	if _baby_real_hurtbox:
		if not _baby_real_hurtbox.area_entered.is_connected(_on_baby_real_hurtbox_area_entered):
			_baby_real_hurtbox.area_entered.connect(_on_baby_real_hurtbox_area_entered)
	if _real_hurtbox:
		if not _real_hurtbox.area_entered.is_connected(_on_real_hurtbox_area_entered):
			_real_hurtbox.area_entered.connect(_on_real_hurtbox_area_entered)
	# Phase 3 hitbox 信号
	if _kick_hitbox:
		if not _kick_hitbox.body_entered.is_connected(_on_kick_hitbox_body_entered):
			_kick_hitbox.body_entered.connect(_on_kick_hitbox_body_entered)
	for area: Area2D in [_attack1_area, _attack2_area, _attack3_area, _run_slash_hitbox]:
		if area and not area.body_entered.is_connected(_on_attack_hitbox_body_entered):
			area.body_entered.connect(_on_attack_hitbox_body_entered)
	if _ground_hitbox:
		if not _ground_hitbox.body_entered.is_connected(_on_ground_hitbox_body_entered):
			_ground_hitbox.body_entered.connect(_on_ground_hitbox_body_entered)
	if _scythe_detect_area:
		if not _scythe_detect_area.body_entered.is_connected(_on_scythe_area_body_entered):
			_scythe_detect_area.body_entered.connect(_on_scythe_area_body_entered)


func _on_baby_real_hurtbox_area_entered(area: Area2D) -> void:
	if not _baby_realhurtbox_active:
		return
	if not _is_ghostfist_hitbox(area):
		return
	apply_real_damage(1)


func _on_real_hurtbox_area_entered(area: Area2D) -> void:
	if not _is_ghostfist_hitbox(area):
		return
	apply_real_damage(1)


func _is_ghostfist_hitbox(area: Area2D) -> bool:
	if area.is_in_group("ghost_fist_hitbox"):
		return true
	var parent: Node = area.get_parent()
	if parent != null and parent.get("weapon_id") == &"ghost_fist":
		return true
	return false


func _on_kick_hitbox_body_entered(body: Node2D) -> void:
	if not _atk_hit_window_open:
		return
	if body.is_in_group("player"):
		if body.has_method("apply_damage"):
			body.call("apply_damage", 1, global_position)
		if body is CharacterBody2D:
			var kb_dir: float = signf(body.global_position.x - global_position.x)
			if kb_dir == 0.0:
				kb_dir = 1.0
			body.velocity.x = kb_dir * p3_kick_knockback_px * 5.0


func _on_attack_hitbox_body_entered(body: Node2D) -> void:
	if not _atk_hit_window_open:
		return
	if body.is_in_group("player") and body.has_method("apply_damage"):
		body.call("apply_damage", 1, global_position)


func _on_ground_hitbox_body_entered(body: Node2D) -> void:
	if body.is_in_group("player") and body.has_method("apply_damage"):
		body.call("apply_damage", 1, global_position)


func _on_scythe_area_body_entered(body: Node2D) -> void:
	if not _atk_hit_window_open:
		return
	if body.is_in_group("player") and body.has_method("apply_damage"):
		body.call("apply_damage", 1, global_position)


# ═══════════════════════════════════════
# Hitbox 管理
# ═══════════════════════════════════════

func _set_hitbox_enabled(area: Area2D, enabled: bool) -> void:
	if area == null:
		return
	area.set_deferred("monitoring", enabled)
	for child in area.get_children():
		if child is CollisionShape2D:
			child.set_deferred("disabled", not enabled)


func _disable_all_hitboxes() -> void:
	var all_hitboxes: Array[Area2D] = [
		_baby_real_hurtbox, _baby_attack_area, _baby_explosion_area,
		_ground_hitbox, _kick_hitbox,
		_attack1_area, _attack2_area, _attack3_area, _run_slash_hitbox
	]
	for hb: Area2D in all_hitboxes:
		_set_hitbox_enabled(hb, false)
	# RealHurtbox 在 Phase 1 默认 disabled
	_set_hitbox_enabled(_real_hurtbox, false)
	_atk_hit_window_open = false


func _set_baby_realhurtbox(active: bool) -> void:
	_baby_realhurtbox_active = active
	_set_hitbox_enabled(_baby_real_hurtbox, active)


func _set_realhurtbox_enabled(enabled: bool) -> void:
	_set_hitbox_enabled(_real_hurtbox, enabled)


func _close_all_combo_hitboxes() -> void:
	_set_hitbox_enabled(_attack1_area, false)
	_set_hitbox_enabled(_attack2_area, false)
	_set_hitbox_enabled(_attack3_area, false)
	_atk_hit_window_open = false


# ═══════════════════════════════════════
# 骨骼跟随
# ═══════════════════════════════════════

func _sync_hurtboxes() -> void:
	match current_phase:
		Phase.PHASE1:
			if _baby_realhurtbox_active and _baby_anim_driver:
				var core_pos: Vector2 = _baby_anim_driver.get_bone_world_position("core")
				if core_pos != Vector2.ZERO:
					_baby_real_hurtbox.global_position = core_pos
		Phase.PHASE2:
			if _anim_driver:
				var hale_pos: Vector2 = _anim_driver.get_bone_world_position("hale")
				if hale_pos != Vector2.ZERO:
					_real_hurtbox.global_position = hale_pos
		Phase.PHASE3:
			_sync_phase3_hitboxes()


func _sync_phase3_hitboxes() -> void:
	if current_phase != Phase.PHASE3:
		return
	if _anim_driver == null:
		return
	var leg_pos: Vector2 = _anim_driver.get_bone_world_position("leg")
	if leg_pos != Vector2.ZERO:
		_kick_hitbox.global_position = leg_pos
	var hale_pos: Vector2 = _anim_driver.get_bone_world_position("hale")
	if hale_pos != Vector2.ZERO:
		_real_hurtbox.global_position = hale_pos


# ═══════════════════════════════════════
# 朝向
# ═══════════════════════════════════════

func face_toward(target: Node2D) -> void:
	if target == null:
		return
	var dir: float = signf(target.global_position.x - global_position.x)
	if dir == 0.0:
		return
	if _spine_sprite and _spine_sprite is Node2D:
		(_spine_sprite as Node2D).scale.x = absf((_spine_sprite as Node2D).scale.x) * dir


func _sync_facing_to_sprite() -> void:
	if velocity.x == 0.0:
		return
	var dir: float = signf(velocity.x)
	if _spine_sprite and _spine_sprite is Node2D:
		(_spine_sprite as Node2D).scale.x = absf((_spine_sprite as Node2D).scale.x) * dir


# ═══════════════════════════════════════
# 婴儿飞行
# ═══════════════════════════════════════

var _baby_flight_target: Vector2 = Vector2.ZERO

func _on_baby_release() -> void:
	baby_state = BabyState.THROWN
	var player: Node2D = get_priority_attack_target()
	if player:
		_baby_flight_target = player.global_position
	else:
		_baby_flight_target = _baby_statue.global_position + Vector2(200, 0)


func _tick_baby_flight(dt: float) -> void:
	var dir: Vector2 = (_baby_flight_target - _baby_statue.global_position).normalized()
	_baby_statue.global_position += dir * baby_throw_speed * dt
	if _baby_statue.global_position.distance_to(_baby_flight_target) < 15.0:
		_baby_statue.global_position = _baby_flight_target
		baby_state = BabyState.EXPLODED


func _on_baby_become_halo() -> void:
	baby_state = BabyState.HALO
	_set_hitbox_enabled(_baby_body_box, false)
	_set_baby_realhurtbox(true)


# ═══════════════════════════════════════
# 阶段切换
# ═══════════════════════════════════════

func _begin_phase_transition(target_phase: int) -> void:
	hp_locked = true
	_phase_transitioning = true
	velocity = Vector2.ZERO
	_transition_step = 0
	_transition_baby_at_hale = false

	if target_phase == Phase.PHASE2:
		_begin_p1_to_p2()
	elif target_phase == Phase.PHASE3:
		_begin_p2_to_p3()


func _begin_p1_to_p2() -> void:
	# 中断婴儿攻击流
	_set_hitbox_enabled(_baby_attack_area, false)
	_set_hitbox_enabled(_baby_explosion_area, false)
	_set_baby_realhurtbox(false)
	_baby_dash_go_triggered = false
	# 婴儿播放变身动画
	baby_anim_play(&"baby/phase1_to_phase2", false)
	_transition_step = 1  # 等待 baby 变身完成


func _begin_p2_to_p3() -> void:
	# 清理 Phase 2 残留
	for group_name: String in ["ghost_bomb", "ghost_wraith", "ghost_elite", "ghost_tug"]:
		get_tree().call_group(group_name, "queue_free")
	# Boss 播放 Phase 2→3 过渡动画
	anim_play(&"phase2/phase2_to_phase3", false)
	_transition_step = 10  # 等待 spine 事件 phase3_ready


func _tick_phase_transition(dt: float) -> void:
	match _transition_step:
		1:
			# 等待 baby/phase1_to_phase2 播完（或 become_halo 事件触发）
			if baby_state == BabyState.HALO or baby_anim_is_finished(&"baby/phase1_to_phase2"):
				if baby_state != BabyState.HALO:
					_on_baby_become_halo()
				_transition_step = 2
		2:
			# 婴儿飞向 Mark2D_Hale
			var target_pos: Vector2 = _mark_hale.global_position
			var dir: Vector2 = (target_pos - _baby_statue.global_position).normalized()
			_baby_statue.global_position += dir * baby_return_speed * dt
			if _baby_statue.global_position.distance_to(target_pos) < 10.0:
				_baby_statue.global_position = target_pos
				_transition_baby_at_hale = true
				_transition_step = 3
		3:
			# 光环到达 hale → 魔女播放过渡动画
			anim_play(&"phase1/phase1_to_phase2", false)
			_transition_step = 4
		4:
			# 等待魔女过渡动画播完（或 phase2_ready 事件）
			if anim_is_finished(&"phase1/phase1_to_phase2"):
				_finish_phase_transition()
		10:
			# Phase 2→3：等待 phase3_ready 事件（由 Spine 事件触发 _finish_phase_transition）
			if anim_is_finished(&"phase2/phase2_to_phase3"):
				_finish_phase_transition()


func _finish_phase_transition() -> void:
	if not _phase_transitioning:
		return

	if current_phase == Phase.PHASE1:
		# 完成 Phase 1→2
		_baby_statue.visible = false
		_set_realhurtbox_enabled(true)
		current_phase = Phase.PHASE2
		anim_play(&"phase2/idle", true)
	elif current_phase == Phase.PHASE2:
		# 完成 Phase 2→3
		_set_realhurtbox_enabled(true)
		_scythe_in_hand = true
		current_phase = Phase.PHASE3
		anim_play(&"phase3/idle", true)

	_phase_transitioning = false
	hp_locked = false


# ═══════════════════════════════════════
# 死亡
# ═══════════════════════════════════════

func _begin_death() -> void:
	hp_locked = true
	_phase_transitioning = true
	velocity = Vector2.ZERO
	_cleanup_all_instances()
	anim_play(&"phase3/death", false)


func _cleanup_all_instances() -> void:
	for group_name: String in ["ghost_bomb", "ghost_wraith", "ghost_elite", "ghost_tug",
			"witch_scythe", "hell_hand", "ghost_summon"]:
		get_tree().call_group(group_name, "queue_free")


# ═══════════════════════════════════════
# 工具方法
# ═══════════════════════════════════════

static func now_sec() -> float:
	return Time.get_ticks_msec() / 1000.0
