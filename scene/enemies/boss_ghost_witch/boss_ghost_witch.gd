extends MonsterBase
class_name BossGhostWitch

enum Phase { PHASE1 = 1, PHASE2 = 2, PHASE3 = 3 }
enum BabyState { IN_HUG, THROWN, EXPLODED, REPAIRING, DASHING, RETURNING, HALO }

@export var phase2_hp_threshold: int = 20
@export var phase3_hp_threshold: int = 10

@export var detect_range_px: float = 500.0
@export var slow_move_speed: float = 30.0
@export var baby_throw_speed: float = 600.0
@export var baby_return_speed: float = 500.0
@export var baby_repair_duration: float = 2.0
@export var baby_dash_speed: float = 420.0
@export var baby_post_dash_wait: float = 0.7

@export var scythe_slash_cooldown: float = 1.0
@export var tombstone_drop_cooldown: float = 3.0
@export var undead_wind_cooldown: float = 15.0
@export var ghost_tug_cooldown: float = 5.0

var current_phase: int = Phase.PHASE1
var baby_state: int = BabyState.IN_HUG
var _phase_transitioning: bool = false
var _battle_started: bool = true

var _cooldowns: Dictionary = {}
var _baby_timer: float = 0.0
var _baby_dash_wait: float = 0.0
var _baby_target: Node2D = null

@onready var _body_box: Area2D = $BodyBox
@onready var _real_hurtbox: Area2D = $RealHurtbox
@onready var _baby_statue: Node2D = $BabyStatue
@onready var _baby_real_hurtbox: Area2D = $BabyStatue/BabyRealHurtbox
@onready var _baby_attack_area: Area2D = $BabyStatue/BabyAttackArea
@onready var _baby_explosion_area: Area2D = $BabyStatue/BabyExplosionArea
@onready var _mark_hug: Marker2D = $Mark2D_Hug
@onready var _mark_hale: Marker2D = $Mark2D_Hale

func _ready() -> void:
	species_id = &"boss_ghost_witch"
	attribute_type = AttributeType.NORMAL
	size_tier = SizeTier.LARGE
	max_hp = 30
	hp = 30
	weak_hp = 0
	vanish_fusion_required = 0
	super._ready()

	_real_hurtbox.monitoring = true
	_real_hurtbox.monitorable = true
	_baby_real_hurtbox.monitoring = true
	_baby_real_hurtbox.monitorable = true
	_set_phase_hurtbox_state()

func _physics_process(dt: float) -> void:
	if not _battle_started:
		return
	_sync_phase_anchors()
	if _phase_transitioning:
		move_and_slide()
		return

	match current_phase:
		Phase.PHASE1:
			_tick_phase1(dt)
		Phase.PHASE2:
			_tick_phase2(dt)
		Phase.PHASE3:
			_tick_phase3(dt)

	if not is_on_floor():
		velocity.y += dt * 1200.0
	else:
		velocity.y = maxf(velocity.y, 0.0)
	move_and_slide()

func apply_hit(hit: HitData) -> bool:
	if hit == null:
		return false
	if hit.weapon_id != &"ghost_fist":
		_flash_once()
		return false
	apply_real_damage(max(hit.damage, 1))
	return true

func on_chain_hit(_player: Node, _slot: int) -> int:
	_flash_once()
	return 0

func apply_real_damage(amount: int) -> void:
	if hp_locked or _phase_transitioning:
		_flash_once()
		return
	hp = maxi(hp - amount, 0)
	_flash_once()

	if current_phase == Phase.PHASE1 and hp <= phase2_hp_threshold:
		_begin_phase_transition(Phase.PHASE2)
	elif current_phase == Phase.PHASE2 and hp <= phase3_hp_threshold:
		_begin_phase_transition(Phase.PHASE3)
	elif hp <= 0:
		_begin_death()

func _begin_phase_transition(next_phase: int) -> void:
	if _phase_transitioning:
		return
	_phase_transitioning = true
	hp_locked = true
	velocity = Vector2.ZERO
	await get_tree().create_timer(0.8).timeout
	current_phase = next_phase
	if current_phase == Phase.PHASE2:
		baby_state = BabyState.HALO
		_baby_statue.visible = false
	if current_phase == Phase.PHASE3:
		_baby_statue.visible = false
	_set_phase_hurtbox_state()
	hp_locked = false
	_phase_transitioning = false

func _begin_death() -> void:
	queue_free()

func _set_phase_hurtbox_state() -> void:
	if current_phase == Phase.PHASE1:
		_real_hurtbox.monitorable = false
		_real_hurtbox.get_node("CollisionShape2D").set_deferred("disabled", true)
		_baby_real_hurtbox.monitorable = true
		_baby_real_hurtbox.get_node("CollisionShape2D").set_deferred("disabled", false)
	else:
		_real_hurtbox.monitorable = true
		_real_hurtbox.get_node("CollisionShape2D").set_deferred("disabled", false)
		_baby_real_hurtbox.monitorable = false
		_baby_real_hurtbox.get_node("CollisionShape2D").set_deferred("disabled", true)

func _tick_phase1(dt: float) -> void:
	var player: Node2D = get_priority_attack_target()
	if player == null:
		velocity.x = 0.0
		return

	if baby_state == BabyState.IN_HUG:
		var dist_x: float = abs(player.global_position.x - global_position.x)
		if dist_x <= detect_range_px:
			baby_state = BabyState.THROWN
			_baby_target = player
	elif baby_state == BabyState.THROWN:
		if _baby_target == null or not is_instance_valid(_baby_target):
			baby_state = BabyState.RETURNING
		else:
			var dir: Vector2 = (_baby_target.global_position - _baby_statue.global_position).normalized()
			_baby_statue.global_position += dir * baby_throw_speed * dt
			if _baby_statue.global_position.distance_to(_baby_target.global_position) < 24.0:
				baby_state = BabyState.EXPLODED
				_baby_timer = baby_repair_duration
				_baby_explosion_area.get_node("CollisionShape2D").set_deferred("disabled", false)
	elif baby_state == BabyState.EXPLODED:
		_baby_timer -= dt
		if _baby_timer <= 0.0:
			_baby_explosion_area.get_node("CollisionShape2D").set_deferred("disabled", true)
			baby_state = BabyState.DASHING
	elif baby_state == BabyState.DASHING:
		var dash_dir: float = signf(player.global_position.x - _baby_statue.global_position.x)
		if is_zero_approx(dash_dir):
			dash_dir = 1.0
		_baby_statue.global_position.x += dash_dir * baby_dash_speed * dt
		if abs(_baby_statue.global_position.x - player.global_position.x) < 16.0:
			baby_state = BabyState.RETURNING
	elif baby_state == BabyState.RETURNING:
		var to_hug: Vector2 = _mark_hug.global_position - _baby_statue.global_position
		var step: float = baby_return_speed * dt
		if to_hug.length() <= step:
			_baby_statue.global_position = _mark_hug.global_position
			baby_state = BabyState.IN_HUG
		else:
			_baby_statue.global_position += to_hug.normalized() * step

	velocity.x = signf(player.global_position.x - global_position.x) * slow_move_speed

func _tick_phase2(_dt: float) -> void:
	var player: Node2D = get_priority_attack_target()
	if player == null:
		velocity.x = 0.0
		return
	var dist: float = abs(player.global_position.x - global_position.x)
	if dist <= 100.0 and _cooldown_ready("scythe"):
		_set_cooldown("scythe", scythe_slash_cooldown)
	elif dist <= 500.0 and _cooldown_ready("tombstone"):
		_set_cooldown("tombstone", tombstone_drop_cooldown)
	elif dist <= 300.0 and dist > 100.0 and _cooldown_ready("wind"):
		_set_cooldown("wind", undead_wind_cooldown)
	elif dist > 500.0 and _cooldown_ready("tug"):
		_set_cooldown("tug", ghost_tug_cooldown)
	velocity.x = signf(player.global_position.x - global_position.x) * slow_move_speed

func _tick_phase3(_dt: float) -> void:
	var player: Node2D = get_priority_attack_target()
	if player == null:
		velocity.x = 0.0
		return
	velocity.x = signf(player.global_position.x - global_position.x) * (slow_move_speed + 25.0)

func _sync_phase_anchors() -> void:
	if current_phase == Phase.PHASE1 and baby_state == BabyState.IN_HUG:
		_baby_statue.global_position = _mark_hug.global_position
	elif current_phase >= Phase.PHASE2:
		_real_hurtbox.global_position = _mark_hale.global_position

func _cooldown_ready(key: String) -> bool:
	var now_s: float = Time.get_ticks_msec() / 1000.0
	var ready_at: float = float(_cooldowns.get(key, 0.0))
	return now_s >= ready_at

func _set_cooldown(key: String, cooldown_sec: float) -> void:
	var now_s: float = Time.get_ticks_msec() / 1000.0
	_cooldowns[key] = now_s + cooldown_sec

func _flash_once() -> void:
	modulate = Color(1.0, 0.7, 0.7, 1.0)
	await get_tree().create_timer(0.08).timeout
	if is_inside_tree():
		modulate = Color(1, 1, 1, 1)
