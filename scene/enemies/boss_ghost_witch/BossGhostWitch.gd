extends MonsterBase
class_name BossGhostWitch

enum Phase { PHASE1 = 1, PHASE2 = 2, PHASE3 = 3 }
enum BabyState { IN_HUG, THROWN, EXPLODED, REPAIRING, DASHING, POST_DASH_WAIT, WINDING_UP, RETURNING, HALO }

const PHASE2_HP_THRESHOLD: int = 20
const PHASE3_HP_THRESHOLD: int = 10

@export var detect_range_px: float = 500.0
@export var slow_move_speed: float = 30.0
@export var baby_throw_speed: float = 600.0
@export var baby_dash_speed: float = 400.0
@export var baby_post_dash_wait: float = 0.7
@export var baby_return_speed: float = 500.0
@export var start_attack_loop_duration: float = 2.0

@export_group("Phase 2")
@export var ghost_tug_cooldown: float = 8.0
@export var ghost_tug_pull_speed: float = 200.0
@export var ghost_bomb_interval: float = 5.0
@export var ghost_bomb_light_energy: float = 1.0
@export var scythe_slash_cooldown: float = 3.0
@export var tombstone_drop_cooldown: float = 10.0
@export var tombstone_fall_duration: float = 0.6
@export var tombstone_hover_duration: float = 1.0
@export var tombstone_offset_x_range: float = 80.0
@export var tombstone_offset_y: float = 200.0
@export var tombstone_stagger_duration: float = 1.5
@export var undead_wind_cooldown: float = 12.0
@export var undead_wind_spawn_duration: float = 6.0
@export var undead_wind_total_count: int = 8

@export_group("Phase 3")
@export var p3_move_speed: float = 120.0
@export var p3_run_speed: float = 250.0
@export var p3_dash_speed: float = 800.0
@export var p3_dash_charge_time: float = 0.5
@export var p3_dash_cooldown: float = 6.0
@export var p3_combo_cooldown: float = 4.0
@export var p3_kick_cooldown: float = 3.0
@export var p3_run_slash_overshoot_px: float = 200.0
@export var p3_kick_knockback_px: float = 300.0
@export var p3_imprison_cooldown: float = 15.0
@export var p3_imprison_escape_time: float = 3.0
@export var p3_imprison_stun_time: float = 2.0
@export var p3_scythe_track_interval: float = 1.0
@export var p3_scythe_track_count: int = 3
@export var p3_scythe_fly_speed: float = 300.0
@export var p3_scythe_return_speed: float = 500.0
@export var p3_summon_circle_count: int = 5
@export var p3_summon_wave_count: int = 3
@export var p3_summon_cooldown: float = 20.0

var current_phase: int = Phase.PHASE1
var baby_state: int = BabyState.IN_HUG
var _phase_transitioning: bool = false
var _battle_started: bool = false
var _baby_dash_go_triggered: bool = false
var _baby_flight_target: Vector2 = Vector2.ZERO
var _scythe_in_hand: bool = true
var _scythe_instance: Node2D = null
var _scythe_recall_requested: bool = false
var _hell_hand_instance: Node2D = null
var _player_imprisoned: bool = false

var _current_anim: StringName = &""
var _current_anim_finished: bool = false
var _current_anim_loop: bool = false

# 婴儿石像动画状态跟踪（防止每帧重复 set_animation 导致动画永远无法完成）
var _current_baby_anim: StringName = &""
var _current_baby_anim_finished: bool = false
var _current_baby_anim_loop: bool = false

# 动画驱动（与修女蛇同款）
var _anim_driver: AnimDriverSpine = null
var _anim_mock: AnimDriverMock = null

var _witch_scythe_scene: PackedScene = preload("res://scene/enemies/boss_ghost_witch/WitchScythe.tscn")
var _hell_hand_scene: PackedScene = preload("res://scene/enemies/boss_ghost_witch/HellHand.tscn")
var _ghost_tug_scene: PackedScene = preload("res://scene/enemies/boss_ghost_witch/GhostTug.tscn")
var _ghost_bomb_scene: PackedScene = preload("res://scene/enemies/boss_ghost_witch/GhostBomb.tscn")
var _ghost_wraith_scene: PackedScene = preload("res://scene/enemies/boss_ghost_witch/GhostWraith.tscn")
var _ghost_elite_scene: PackedScene = preload("res://scene/enemies/boss_ghost_witch/GhostElite.tscn")
var _ghost_summon_scene: PackedScene = preload("res://scene/enemies/boss_ghost_witch/GhostSummon.tscn")

@onready var _spine_sprite: Node = $SpineSprite
@onready var _body_box: Area2D = $BodyBox
@onready var _real_hurtbox: Area2D = $RealHurtbox
@onready var _scythe_detect_area: Area2D = $ScytheDetectArea
@onready var _ground_hitbox: Area2D = $GroundHitbox
@onready var _mark_hug: Marker2D = $Mark2D_Hug
@onready var _mark_hale: Marker2D = $Mark2D_Hale
@onready var _baby_statue: Node2D = $BabyStatue
@onready var _baby_spine: Node = $BabyStatue/SpineSprite
@onready var _baby_real_hurtbox: Area2D = $BabyStatue/BabyRealHurtbox
@onready var _baby_attack_area: Area2D = $BabyStatue/BabyAttackArea
@onready var _baby_explosion_area: Area2D = $BabyStatue/BabyExplosionArea
@onready var _baby_detect_area: Area2D = $BabyStatue/BabyDetectArea
@onready var _kick_hitbox: Area2D = $KickHitbox
@onready var _attack1_area: Area2D = $Attack1Area
@onready var _attack2_area: Area2D = $Attack2Area
@onready var _attack3_area: Area2D = $Attack3Area
@onready var _run_slash_hitbox: Area2D = $RunSlashHitbox


func _ready() -> void:
	species_id = &"boss_ghost_witch"
	entity_type = EntityType.MONSTER
	size_tier = SizeTier.LARGE
	attribute_type = AttributeType.NORMAL
	has_hp = true
	max_hp = 30
	hp = 30
	weak_hp = 0  # Boss 不使用 weak 机制
	vanish_fusion_required = 0  # 不可泯灭
	floor_snap_length = 0.0

	super._ready()
	add_to_group("boss_ghost_witch")
	add_to_group("boss")

	# 初始化动画驱动
	_setup_anim_drivers()

	# 关闭所有攻击 hitbox
	_set_hitbox_enabled(_real_hurtbox, false)
	_set_hitbox_enabled(_baby_real_hurtbox, false)
	_set_hitbox_enabled(_ground_hitbox, false)
	_set_hitbox_enabled(_kick_hitbox, false)
	_set_hitbox_enabled(_attack1_area, false)
	_set_hitbox_enabled(_attack2_area, false)
	_set_hitbox_enabled(_attack3_area, false)
	_set_hitbox_enabled(_run_slash_hitbox, false)

	# 初始动画
	anim_play(&"phase1/idle", true)


func _setup_anim_drivers() -> void:
	# 主 SpineSprite 动画驱动
	if _is_spine_sprite_compatible(_spine_sprite):
		_anim_driver = AnimDriverSpine.new()
		add_child(_anim_driver)
		_anim_driver.setup(_spine_sprite)
		_anim_driver.anim_completed.connect(_on_anim_completed)
		if _spine_sprite.has_signal("animation_event"):
			_spine_sprite.animation_event.connect(_on_spine_event)
	else:
		_anim_mock = AnimDriverMock.new()
		add_child(_anim_mock)
		_anim_mock.anim_completed.connect(_on_anim_completed)

	# 婴儿石像 Spine 事件（不需要单独 AnimDriverSpine，事件监听即可）
	if _baby_spine != null and _is_spine_sprite_compatible(_baby_spine):
		if _baby_spine.has_signal("animation_event"):
			_baby_spine.animation_event.connect(_on_baby_spine_event)


func _is_spine_sprite_compatible(node: Node) -> bool:
	if node == null:
		return false
	if String(node.get_class()) == "SpineSprite":
		return true
	# 兜底：按能力探测
	return node.has_method("get_animation_state")


func _physics_process(dt: float) -> void:
	# 光照系统（保留 MonsterBase 兼容）
	if light_counter > 0.0:
		light_counter -= dt
		light_counter = max(light_counter, 0.0)
	_thunder_processed_this_frame = false

	# Mock 驱动 tick
	if _anim_mock:
		_anim_mock.tick(dt)

	# 骨骼跟随
	_update_bone_follow()

	# 婴儿石像飞行（THROWN 状态下向目标移动）
	_tick_baby_flight(dt)

	# 婴儿石像位置管理
	_update_halo_baby()

	# 伤害判定
	_update_damage_hitboxes()

	# 重力
	if not is_on_floor():
		velocity.y += dt * 1200.0
	else:
		velocity.y = maxf(velocity.y, 0.0)

	move_and_slide()
	# 不调用 super._physics_process()
	# BeehaveTree 由其自身 _physics_process 驱动


func _do_move(_dt: float) -> void:
	pass


func _update_halo_baby() -> void:
	if baby_state == BabyState.HALO:
		_baby_statue.global_position = _mark_hale.global_position
	elif baby_state == BabyState.IN_HUG:
		_baby_statue.global_position = _mark_hug.global_position


func _tick_baby_flight(dt: float) -> void:
	if baby_state != BabyState.THROWN:
		return
	var baby := _baby_statue
	if baby == null:
		return
	var dir := (_baby_flight_target - baby.global_position).normalized()
	baby.global_position += dir * baby_throw_speed * dt
	# 到达目标位置 → 落地爆炸
	if baby.global_position.distance_to(_baby_flight_target) < 15.0:
		baby.global_position = _baby_flight_target
		baby_state = BabyState.EXPLODED


func _update_damage_hitboxes() -> void:
	for hb: Area2D in [_kick_hitbox, _attack1_area, _attack2_area, _attack3_area, _run_slash_hitbox, _ground_hitbox, _baby_attack_area, _baby_explosion_area]:
		if hb == null or not hb.monitoring:
			continue
		for body in hb.get_overlapping_bodies():
			if body != null and body.is_in_group("player") and body.has_method("apply_damage"):
				body.call("apply_damage", 1, hb.global_position)


func _update_bone_follow() -> void:
	if current_phase == Phase.PHASE1:
		_baby_real_hurtbox.global_position = _baby_statue.global_position
	else:
		if _anim_driver != null:
			var hale_pos: Vector2 = _anim_driver.get_bone_world_position("hale")
			if hale_pos != Vector2.ZERO:
				_real_hurtbox.global_position = hale_pos
			else:
				_real_hurtbox.global_position = _mark_hale.global_position
		else:
			_real_hurtbox.global_position = _mark_hale.global_position
	if current_phase == Phase.PHASE3:
		_kick_hitbox.global_position = global_position + Vector2(16.0, 0.0)


func apply_real_damage(amount: int) -> void:
	if hp_locked:
		_flash_once()
		return
	hp = maxi(hp - amount, 0)
	_flash_once()
	if current_phase == Phase.PHASE3 and not _scythe_in_hand:
		_scythe_recall_requested = true
	if current_phase == Phase.PHASE1 and hp <= PHASE2_HP_THRESHOLD:
		_begin_phase_transition(Phase.PHASE2)
	elif current_phase == Phase.PHASE2 and hp <= PHASE3_HP_THRESHOLD:
		_begin_phase_transition(Phase.PHASE3)
	elif hp <= 0:
		_begin_death()


func apply_hit(hit: HitData) -> bool:
	if hit == null or hit.weapon_id != &"ghost_fist":
		_flash_once()
		return false
	apply_real_damage(hit.damage)
	return true


func on_chain_hit(_p: Node, _s: int) -> int:
	_flash_once()
	return 0


func _begin_phase_transition(target: int) -> void:
	_phase_transitioning = true
	hp_locked = true
	velocity = Vector2.ZERO
	if target == Phase.PHASE2:
		anim_play(&"phase1/phase1_to_phase2", false)
		baby_state = BabyState.HALO
		_set_hitbox_enabled(_baby_real_hurtbox, true)
		_set_hitbox_enabled(_real_hurtbox, true)
		current_phase = Phase.PHASE2
		_baby_statue.visible = false
		anim_play(&"phase2/idle", true)
	else:
		_cleanup_phase2_instances()
		anim_play(&"phase2/phase2_to_phase3", false)
		current_phase = Phase.PHASE3
		_scythe_in_hand = true
		anim_play(&"phase3/idle", true)
	hp_locked = false
	_phase_transitioning = false


func _cleanup_phase2_instances() -> void:
	for g in ["ghost_tug", "ghost_bomb", "ghost_wraith", "ghost_elite"]:
		for n in get_tree().get_nodes_in_group(g):
			if is_instance_valid(n):
				n.queue_free()


func _begin_death() -> void:
	hp_locked = true
	for g in ["ghost_tug", "ghost_bomb", "ghost_wraith", "ghost_elite", "witch_scythe", "hell_hand", "ghost_summon"]:
		for n in get_tree().get_nodes_in_group(g):
			if is_instance_valid(n):
				n.queue_free()
	anim_play(&"phase3/death", false)
	set_physics_process(false)


func _set_hitbox_enabled(area: Area2D, enabled: bool) -> void:
	if area == null:
		return
	area.set_deferred("monitoring", enabled)
	area.set_deferred("monitorable", enabled)


# ═══ 动画系统（与修女蛇同款接口）═══

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


func baby_anim_play(anim_name: StringName, loop: bool) -> void:
	if _baby_spine == null:
		return
	# 去重：同名同循环且未完成 → 跳过，避免每帧重置动画
	if _current_baby_anim == anim_name and not _current_baby_anim_finished and _current_baby_anim_loop == loop:
		return
	_current_baby_anim = anim_name
	_current_baby_anim_finished = false
	_current_baby_anim_loop = loop
	# 婴儿直接通过 SpineSprite 的 AnimationState 播放
	if _is_spine_sprite_compatible(_baby_spine):
		var anim_state: Object = null
		if _baby_spine.has_method("get_animation_state"):
			anim_state = _baby_spine.get_animation_state()
		if anim_state != null and anim_state.has_method("set_animation"):
			anim_state.set_animation(String(anim_name), loop, 0)


func anim_is_finished(anim_name: StringName) -> bool:
	return _current_anim == anim_name and _current_anim_finished


func baby_anim_is_finished(anim_name: StringName) -> bool:
	# 名称不匹配 → 不是我们关心的动画
	if _current_baby_anim != anim_name:
		return false
	# 已经标记完成
	if _current_baby_anim_finished:
		return true
	# 婴儿的完成检测通过轮询 SpineSprite 的 TrackEntry
	if _baby_spine == null:
		return true
	if not _is_spine_sprite_compatible(_baby_spine):
		return true
	var anim_state: Object = null
	if _baby_spine.has_method("get_animation_state"):
		anim_state = _baby_spine.get_animation_state()
	if anim_state == null:
		return true
	var entry: Object = null
	if anim_state.has_method("get_current"):
		entry = anim_state.get_current(0)
	if entry == null:
		return true
	# 检查当前轨道的动画是否完成
	var done: bool = false
	if entry.has_method("is_complete"):
		done = entry.is_complete()
	elif entry.has_method("isComplete"):
		done = entry.isComplete()
	if done:
		_current_baby_anim_finished = true
	return done


func _on_anim_completed(_track: int, anim_name: StringName) -> void:
	if anim_name == _current_anim:
		_current_anim_finished = true


# ═══ Spine 事件处理（与修女蛇同款事件提取）═══

func _on_spine_event(a1 = null, a2 = null, a3 = null, a4 = null) -> void:
	var e := _extract_spine_event_name(a1, a2, a3, a4)
	match e:
		# Phase 1 start_attack 事件
		&"start_attack_hitbox_on": _set_hitbox_enabled(_scythe_detect_area, true)
		&"start_attack_hitbox_off": _set_hitbox_enabled(_scythe_detect_area, false)
		&"battle_start": _battle_started = true
		&"baby_release": baby_state = BabyState.THROWN
		&"throw_done": pass
		&"baby_return": baby_state = BabyState.IN_HUG
		# Phase 1→2 过渡
		&"phase2_ready":
			_phase_transitioning = false
			hp_locked = false
		# Phase 2 事件
		&"scythe_hitbox_on": _set_hitbox_enabled(_scythe_detect_area, true)
		&"scythe_hitbox_off": _set_hitbox_enabled(_scythe_detect_area, false)
		&"ground_hitbox_on": _set_hitbox_enabled(_ground_hitbox, true)
		&"ground_hitbox_off": _set_hitbox_enabled(_ground_hitbox, false)
		# Phase 2→3 过渡
		&"phase3_ready":
			_phase_transitioning = false
			hp_locked = false
		# Phase 3 事件
		&"kick_hitbox_on": _set_hitbox_enabled(_kick_hitbox, true)
		&"kick_hitbox_off": _set_hitbox_enabled(_kick_hitbox, false)
		&"combo1_hitbox_on": _set_hitbox_enabled(_attack1_area, true)
		&"combo1_hitbox_off": _set_hitbox_enabled(_attack1_area, false)
		&"combo2_hitbox_on": _set_hitbox_enabled(_attack2_area, true)
		&"combo2_hitbox_off": _set_hitbox_enabled(_attack2_area, false)
		&"combo3_hitbox_on": _set_hitbox_enabled(_attack3_area, true)
		&"combo3_hitbox_off": _set_hitbox_enabled(_attack3_area, false)
		&"dash_hitbox_on": _set_hitbox_enabled(_run_slash_hitbox, true)
		&"dash_hitbox_off": _set_hitbox_enabled(_run_slash_hitbox, false)
		&"slash_hitbox_on": _set_hitbox_enabled(_run_slash_hitbox, true)
		&"slash_hitbox_off": _set_hitbox_enabled(_run_slash_hitbox, false)
		&"death_finished": anim_play(&"phase3/death_loop", true)


func _on_baby_spine_event(a1 = null, a2 = null, a3 = null, a4 = null) -> void:
	var e := _extract_spine_event_name(a1, a2, a3, a4)
	match e:
		&"dash_go": _baby_dash_go_triggered = true
		&"dash_hitbox_on": _set_hitbox_enabled(_baby_attack_area, true)
		&"explode_hitbox_on": _set_hitbox_enabled(_baby_explosion_area, true)
		&"explode_hitbox_off": _set_hitbox_enabled(_baby_explosion_area, false)
		&"realhurtbox_on": _set_hitbox_enabled(_baby_real_hurtbox, true)
		&"realhurtbox_off": _set_hitbox_enabled(_baby_real_hurtbox, false)


func _extract_spine_event_name(a1 = null, a2 = null, a3 = null, a4 = null) -> StringName:
	## 从 Spine animation_event 信号参数中提取事件名
	## 与 StoneMaskBird/ChimeraNunSnake 同款提取方式
	var spine_event: Object = null
	for a in [a1, a2, a3, a4]:
		if a == null:
			continue
		if a is Object and a.has_method("get_data"):
			spine_event = a
			break
	if spine_event == null:
		return &""
	var data: Object = spine_event.get_data()
	if data == null:
		return &""
	var event_name: String = ""
	if data.has_method("get_event_name"):
		event_name = data.get_event_name()
	elif data.has_method("getEventName"):
		event_name = data.getEventName()
	elif data.has_method("get_name"):
		event_name = data.get_name()
	elif data.has_method("getName"):
		event_name = data.getName()
	if event_name == "":
		return &""
	return StringName(event_name)


# ═══ 辅助方法 ═══

func face_toward(target: Node2D) -> void:
	if target == null:
		return
	var dx := target.global_position.x - global_position.x
	if absf(dx) < 2.0:
		return
	if _spine_sprite != null:
		_spine_sprite.scale.x = absf(_spine_sprite.scale.x) * (1.0 if dx > 0.0 else -1.0)


func _close_all_combo_hitboxes() -> void:
	_set_hitbox_enabled(_attack1_area, false)
	_set_hitbox_enabled(_attack2_area, false)
	_set_hitbox_enabled(_attack3_area, false)


func _set_baby_realhurtbox(enabled: bool) -> void:
	_set_hitbox_enabled(_baby_real_hurtbox, enabled)


func _set_realhurtbox_enabled(enabled: bool) -> void:
	_set_hitbox_enabled(_real_hurtbox, enabled)


func _exit_tree() -> void:
	if _player_imprisoned:
		var p := get_priority_attack_target()
		if p != null and p.has_method("set_external_control_frozen"):
			p.call("set_external_control_frozen", false)
