extends MonsterBase
class_name BossGhostWitch

enum Phase { PHASE1 = 1, PHASE2 = 2, PHASE3 = 3 }
enum BabyState { IN_HUG, THROWN, EXPLODED, REPAIRING, DASHING, POST_DASH_WAIT, WINDING_UP, RETURNING, HALO }

@export var phase2_hp_threshold: int = 20
@export var phase3_hp_threshold: int = 10

@export var detect_range_px: float = 500.0
@export var slow_move_speed: float = 30.0
@export var baby_throw_speed: float = 600.0
@export var baby_dash_speed: float = 400.0
@export var baby_post_dash_wait: float = 0.7
@export var baby_return_speed: float = 500.0
@export var start_attack_loop_duration: float = 4.0

@export var phase2_move_speed: float = 90.0
@export var phase3_move_speed: float = 120.0

var current_phase: int = Phase.PHASE1
var baby_state: int = BabyState.IN_HUG
var _phase_transitioning: bool = false
var _battle_started: bool = false
var _baby_realhurtbox_active: bool = false
var _baby_dash_go_triggered: bool = false

var _active_anim: StringName = &""
var _active_baby_anim: StringName = &""
var _anim_end_ms: int = 0
var _baby_anim_end_ms: int = 0

var _baby_dash_target: Vector2 = Vector2.ZERO
var _baby_dash_origin: Vector2 = Vector2.ZERO
var _baby_wait_until_ms: int = 0
var _thrown_velocity: Vector2 = Vector2.ZERO

var _scythe_in_hand: bool = true
var _scythe_recall_requested: bool = false

@onready var _spine_sprite: Node2D = $SpineSprite
@onready var _baby_statue: Node2D = $BabyStatue
@onready var _baby_spine: Node2D = $BabyStatue/SpineSprite
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
	_disable_all_hitboxes()
	_enter_phase1()
	if _real_hurtbox != null:
		_real_hurtbox.area_entered.connect(_on_real_hurtbox_area_entered)
	if _baby_real_hurtbox != null:
		_baby_real_hurtbox.area_entered.connect(_on_baby_real_hurtbox_area_entered)

func _physics_process(dt: float) -> void:
	if light_counter > 0.0:
		light_counter = maxf(light_counter - dt, 0.0)
	_sync_hurtboxes()
	if current_phase == Phase.PHASE1 and baby_state == BabyState.IN_HUG:
		_baby_statue.global_position = _mark_hug.global_position
	if not is_on_floor():
		velocity.y += 1200.0 * dt
	else:
		velocity.y = maxf(velocity.y, 0.0)
	move_and_slide()

func _disable_all_hitboxes() -> void:
	_set_hitbox_enabled(_real_hurtbox, false)
	_set_hitbox_enabled(_baby_real_hurtbox, false)
	_set_hitbox_enabled(_baby_attack_area, false)
	_set_hitbox_enabled(_baby_explosion_area, false)
	_set_hitbox_enabled(_ground_hitbox, false)

func _set_hitbox_enabled(area: Area2D, enabled: bool) -> void:
	if area == null:
		return
	area.monitoring = enabled
	area.monitorable = enabled
	for c in area.get_children():
		var cs := c as CollisionShape2D
		if cs != null:
			cs.disabled = not enabled

func _enter_phase1() -> void:
	current_phase = Phase.PHASE1
	baby_state = BabyState.IN_HUG
	_baby_statue.visible = true
	_set_hitbox_enabled(_real_hurtbox, false)
	_set_baby_realhurtbox(false)
	anim_play(&"phase1/idle", true)
	baby_anim_play(&"baby/idle", true)

func _begin_phase_transition(next_phase: int) -> void:
	if _phase_transitioning:
		return
	hp_locked = true
	_phase_transitioning = true
	velocity.x = 0.0
	if next_phase == Phase.PHASE2:
		anim_play(&"phase1/phase1_to_phase2", false)
		baby_anim_play(&"baby/phase1_to_phase2", false)
	elif next_phase == Phase.PHASE3:
		anim_play(&"phase2/phase2_to_phase3", false)

func finish_phase_transition() -> void:
	if not _phase_transitioning:
		return
	if current_phase == Phase.PHASE1 and hp <= phase2_hp_threshold:
		current_phase = Phase.PHASE2
		_baby_statue.visible = false
		_set_baby_realhurtbox(false)
		_set_hitbox_enabled(_real_hurtbox, true)
		anim_play(&"phase2/idle", true)
	elif current_phase == Phase.PHASE2 and hp <= phase3_hp_threshold:
		current_phase = Phase.PHASE3
		anim_play(&"phase3/idle", true)
	hp_locked = false
	_phase_transitioning = false

func apply_real_damage(amount: int) -> void:
	if hp_locked:
		_flash_once()
		return
	hp = maxi(hp - amount, 0)
	_flash_once()
	if current_phase == Phase.PHASE3 and not _scythe_in_hand:
		_scythe_recall_requested = true
	if current_phase == Phase.PHASE1 and hp <= phase2_hp_threshold:
		_begin_phase_transition(Phase.PHASE2)
	elif current_phase == Phase.PHASE2 and hp <= phase3_hp_threshold:
		_begin_phase_transition(Phase.PHASE3)
	elif hp <= 0:
		_begin_death()

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

func _begin_death() -> void:
	hp_locked = true
	velocity = Vector2.ZERO
	anim_play(&"phase3/death", false)
	queue_free()

func _set_baby_realhurtbox(enabled: bool) -> void:
	_baby_realhurtbox_active = enabled
	_set_hitbox_enabled(_baby_real_hurtbox, enabled)

func _sync_hurtboxes() -> void:
	if current_phase == Phase.PHASE1 and _baby_realhurtbox_active:
		_baby_real_hurtbox.global_position = _baby_statue.global_position
	elif current_phase >= Phase.PHASE2:
		_real_hurtbox.global_position = _mark_hale.global_position

func _on_real_hurtbox_area_entered(area: Area2D) -> void:
	if not _is_ghostfist_hitbox(area):
		return
	apply_real_damage(1)

func _on_baby_real_hurtbox_area_entered(area: Area2D) -> void:
	if not _is_ghostfist_hitbox(area):
		return
	if not _baby_realhurtbox_active:
		return
	apply_real_damage(1)

func _is_ghostfist_hitbox(area: Area2D) -> bool:
	if area == null:
		return false
	if area.is_in_group("ghost_fist_hitbox"):
		return true
	var p := area.get_parent()
	if p != null and p.get_class().to_lower().find("ghost") >= 0:
		return true
	return false

func tick_start_battle() -> int:
	if _battle_started:
		return SUCCESS
	if _active_anim != &"phase1/start_attack" and _active_anim != &"phase1/start_attack_loop" and _active_anim != &"phase1/start_attack_exter":
		anim_play(&"phase1/start_attack", false)
		return RUNNING
	if _active_anim == &"phase1/start_attack" and anim_is_finished(&"phase1/start_attack"):
		if _player_in_scythe_area():
			_damage_player(1)
		anim_play(&"phase1/start_attack_loop", true)
		_anim_end_ms = Time.get_ticks_msec() + int(start_attack_loop_duration * 1000.0)
		return RUNNING
	if _active_anim == &"phase1/start_attack_loop" and Time.get_ticks_msec() >= _anim_end_ms:
		anim_play(&"phase1/start_attack_exter", false)
		return RUNNING
	if _active_anim == &"phase1/start_attack_exter" and anim_is_finished(&"phase1/start_attack_exter"):
		_battle_started = true
		anim_play(&"phase1/idle", true)
		return SUCCESS
	return RUNNING

func tick_phase1_combat(dt: float) -> int:
	var player := get_priority_attack_target()
	if player == null:
		velocity.x = 0.0
		anim_play(&"phase1/idle", true)
		return RUNNING
	if baby_state == BabyState.IN_HUG:
		var h_dist: float = abs(player.global_position.x - global_position.x)
		if h_dist <= detect_range_px:
			baby_state = BabyState.THROWN
			_baby_dash_origin = _mark_hug.global_position
			_baby_dash_target = player.global_position
			_thrown_velocity = (_baby_dash_target - _baby_dash_origin).normalized() * baby_throw_speed
			baby_anim_play(&"baby/throw", false)
			anim_play(&"phase1/throw_baby", false)
		else:
			_move_toward_player(player, slow_move_speed, &"phase1/walk", &"phase1/idle")
		return RUNNING
	if baby_state == BabyState.THROWN:
		_baby_statue.global_position += _thrown_velocity * dt
		if _baby_statue.global_position.distance_to(_baby_dash_target) < 16.0:
			baby_state = BabyState.EXPLODED
			baby_anim_play(&"baby/explode", false)
			_set_hitbox_enabled(_baby_explosion_area, true)
			_set_baby_realhurtbox(true)
		return RUNNING
	if baby_state == BabyState.EXPLODED and baby_anim_is_finished(&"baby/explode"):
		baby_state = BabyState.REPAIRING
		baby_anim_play(&"baby/repair", false)
		return RUNNING
	if baby_state == BabyState.REPAIRING and baby_anim_is_finished(&"baby/repair"):
		_set_hitbox_enabled(_baby_explosion_area, false)
		if _player_in_baby_detect_area():
			baby_state = BabyState.DASHING
			_baby_dash_go_triggered = true
			_baby_dash_target = player.global_position
			_set_hitbox_enabled(_baby_attack_area, true)
			baby_anim_play(&"baby/dash_loop", true)
		else:
			baby_state = BabyState.WINDING_UP
			baby_anim_play(&"baby/wind_up", false)
		return RUNNING
	if baby_state == BabyState.DASHING:
		var dir := signf(_baby_dash_target.x - _baby_statue.global_position.x)
		_baby_statue.global_position.x += dir * baby_dash_speed * dt
		_damage_players_in_area(_baby_attack_area, 1)
		if abs(_baby_dash_target.x - _baby_statue.global_position.x) < 10.0:
			baby_state = BabyState.POST_DASH_WAIT
			_baby_wait_until_ms = Time.get_ticks_msec() + int(baby_post_dash_wait * 1000.0)
			baby_anim_play(&"baby/idle", true)
		return RUNNING
	if baby_state == BabyState.POST_DASH_WAIT:
		if Time.get_ticks_msec() >= _baby_wait_until_ms:
			baby_state = BabyState.RETURNING
			_set_hitbox_enabled(_baby_attack_area, false)
			_set_baby_realhurtbox(false)
			baby_anim_play(&"baby/return", true)
		return RUNNING
	if baby_state == BabyState.WINDING_UP and baby_anim_is_finished(&"baby/wind_up"):
		baby_state = BabyState.RETURNING
		_set_baby_realhurtbox(false)
		baby_anim_play(&"baby/return", true)
		return RUNNING
	if baby_state == BabyState.RETURNING:
		_baby_statue.global_position = _baby_statue.global_position.move_toward(_mark_hug.global_position, baby_return_speed * dt)
		if _baby_statue.global_position.distance_to(_mark_hug.global_position) < 8.0:
			baby_state = BabyState.IN_HUG
			baby_anim_play(&"baby/idle", true)
			anim_play(&"phase1/catch_baby", false)
		return RUNNING
	return RUNNING

func tick_phase2_combat(_dt: float) -> int:
	var player := get_priority_attack_target()
	if player == null:
		velocity.x = 0.0
		anim_play(&"phase2/idle", true)
		return RUNNING
	_move_toward_player(player, phase2_move_speed, &"phase2/walk", &"phase2/idle")
	return RUNNING

func tick_phase3_combat(_dt: float) -> int:
	var player := get_priority_attack_target()
	if player == null:
		velocity.x = 0.0
		anim_play(&"phase3/idle", true)
		return RUNNING
	_move_toward_player(player, phase3_move_speed, &"phase3/walk", &"phase3/idle")
	return RUNNING

func _move_toward_player(player: Node2D, move_speed: float, walk_anim: StringName, idle_anim: StringName) -> void:
	var dx := player.global_position.x - global_position.x
	if abs(dx) < 20.0:
		velocity.x = 0.0
		anim_play(idle_anim, true)
	else:
		velocity.x = signf(dx) * move_speed
		face_toward(player)
		anim_play(walk_anim, true)

func face_toward(target: Node2D) -> void:
	if target == null:
		return
	var dir := signf(target.global_position.x - global_position.x)
	if dir != 0.0:
		scale.x = absf(scale.x) * dir

func _damage_players_in_area(area: Area2D, dmg: int) -> void:
	if area == null:
		return
	for b in area.get_overlapping_bodies():
		if b != null and b.is_in_group("player") and b.has_method("apply_damage"):
			b.call("apply_damage", dmg, global_position)

func _player_in_baby_detect_area() -> bool:
	for b in _baby_detect_area.get_overlapping_bodies():
		if b != null and b.is_in_group("player"):
			return true
	return false

func _player_in_scythe_area() -> bool:
	for b in _scythe_detect_area.get_overlapping_bodies():
		if b != null and b.is_in_group("player"):
			return true
	return false

func _damage_player(dmg: int) -> void:
	for b in _scythe_detect_area.get_overlapping_bodies():
		if b != null and b.is_in_group("player") and b.has_method("apply_damage"):
			b.call("apply_damage", dmg, global_position)

func anim_play(anim: StringName, loop: bool, _interruptible: bool = true) -> void:
	if _active_anim == anim and not anim_is_finished(anim):
		return
	_active_anim = anim
	_anim_end_ms = Time.get_ticks_msec() + _anim_duration_ms(anim, loop)

func anim_is_finished(anim: StringName) -> bool:
	if _active_anim != anim:
		return true
	return Time.get_ticks_msec() >= _anim_end_ms

func baby_anim_play(anim: StringName, loop: bool) -> void:
	if _active_baby_anim == anim and not baby_anim_is_finished(anim):
		return
	_active_baby_anim = anim
	_baby_anim_end_ms = Time.get_ticks_msec() + _anim_duration_ms(anim, loop)

func baby_anim_is_finished(anim: StringName) -> bool:
	if _active_baby_anim != anim:
		return true
	return Time.get_ticks_msec() >= _baby_anim_end_ms

func _anim_duration_ms(anim: StringName, loop: bool) -> int:
	if loop:
		return 99999999
	var table := {
		&"phase1/start_attack": 700,
		&"phase1/start_attack_exter": 700,
		&"phase1/throw_baby": 500,
		&"phase1/catch_baby": 500,
		&"phase1/phase1_to_phase2": 1500,
		&"phase2/phase2_to_phase3": 1500,
		&"phase3/death": 1200,
		&"baby/throw": 450,
		&"baby/explode": 700,
		&"baby/repair": 1000,
		&"baby/wind_up": 450,
		&"baby/phase1_to_phase2": 1000,
	}
	return int(table.get(anim, 600))

func _flash_once() -> void:
	# 保留接口，沿用项目风格（无材质时不做额外处理）
	pass
