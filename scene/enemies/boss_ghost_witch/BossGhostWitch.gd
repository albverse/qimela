extends MonsterBase
class_name BossGhostWitch

enum Phase { PHASE1 = 1, PHASE2 = 2, PHASE3 = 3 }
enum BabyState { IN_HUG, THROWN, EXPLODED, REPAIRING, DASHING, POST_DASH_WAIT, WINDING_UP, RETURNING, HALO }

const PHASE2_HP_THRESHOLD: int = 20
const PHASE3_HP_THRESHOLD: int = 10

@export var detect_range_px: float = 500.0
@export var slow_move_speed: float = 30.0
@export var p3_move_speed: float = 120.0
@export var p3_dash_speed: float = 800.0
@export var p3_dash_charge_time: float = 1.0
@export var p3_dash_cooldown: float = 10.0
@export var p3_kick_cooldown: float = 1.0
@export var p3_combo_cooldown: float = 1.0
@export var p3_imprison_cooldown: float = 10.0
@export var p3_summon_cooldown: float = 8.0
@export var p3_scythe_track_interval: float = 1.0
@export var p3_scythe_track_count: int = 3
@export var p3_scythe_fly_speed: float = 300.0
@export var p3_scythe_return_speed: float = 500.0

var current_phase: int = Phase.PHASE1
var baby_state: int = BabyState.IN_HUG
var _phase_transitioning: bool = false
var _battle_started: bool = false
var _baby_dash_go_triggered: bool = false
var _scythe_in_hand: bool = true
var _scythe_instance: Node2D = null
var _scythe_recall_requested: bool = false
var _hell_hand_instance: Node2D = null
var _player_imprisoned: bool = false
var _state: StringName = &"idle"
var _state_end_sec: float = 0.0
var _cooldown_until: Dictionary = {}

@onready var _real_hurtbox: Area2D = $RealHurtbox
@onready var _body_box: Area2D = $BodyBox
@onready var _kick_hitbox: Area2D = $KickHitbox
@onready var _attack1: Area2D = $Attack1Area
@onready var _attack2: Area2D = $Attack2Area
@onready var _attack3: Area2D = $Attack3Area
@onready var _run_slash: Area2D = $RunSlashHitbox
@onready var _scythe_detect: Area2D = $ScytheDetectArea
@onready var _ground_hitbox: Area2D = $GroundHitbox
@onready var _mark_hale: Marker2D = $Mark2D_Hale

const WITCH_SCYTHE_SCENE := preload("res://scene/enemies/boss_ghost_witch/WitchScythe.tscn")
const HELL_HAND_SCENE := preload("res://scene/enemies/boss_ghost_witch/HellHand.tscn")
const GHOST_SUMMON_SCENE := preload("res://scene/enemies/boss_ghost_witch/GhostSummon.tscn")

func _ready() -> void:
	species_id = &"boss_ghost_witch"
	entity_type = EntityType.MONSTER
	size_tier = SizeTier.LARGE
	attribute_type = AttributeType.NORMAL
	max_hp = 30
	weak_hp = 0
	vanish_fusion_required = 999
	super._ready()
	add_to_group("monster")
	_real_hurtbox.area_entered.connect(_on_real_hurtbox_area_entered)
	_set_hitbox_enabled(_kick_hitbox, false)
	_set_hitbox_enabled(_attack1, false)
	_set_hitbox_enabled(_attack2, false)
	_set_hitbox_enabled(_attack3, false)
	_set_hitbox_enabled(_run_slash, false)
	_set_hitbox_enabled(_ground_hitbox, false)
	_set_hitbox_enabled(_real_hurtbox, false)

func _physics_process(dt: float) -> void:
	if _phase_transitioning:
		velocity = Vector2.ZERO
		move_and_slide()
		return
	if _state == &"dead":
		velocity = Vector2.ZERO
		move_and_slide()
		return
	var player := get_priority_attack_target()
	if player == null:
		velocity.x = 0.0
		move_and_slide()
		return
	if not _battle_started:
		_battle_started = true
	_state_machine_tick(dt, player)
	if not is_on_floor():
		velocity.y += 1200.0 * dt
	else:
		velocity.y = 0.0
	move_and_slide()

func _state_machine_tick(_dt: float, player: Node2D) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if _scythe_recall_requested and _scythe_instance and is_instance_valid(_scythe_instance):
		_scythe_instance.call_deferred("recall", global_position)
		_scythe_recall_requested = false
	if current_phase == Phase.PHASE1:
		_state = &"p1_move"
		var dir := signf(player.global_position.x - global_position.x)
		velocity.x = dir * slow_move_speed
		if global_position.distance_to(player.global_position) <= detect_range_px:
			_begin_phase_transition(Phase.PHASE2)
		return
	if current_phase == Phase.PHASE2:
		velocity.x = signf(player.global_position.x - global_position.x) * slow_move_speed
		if now >= _get_cd(&"phase2_to_3"):
			_set_cd(&"phase2_to_3", 9999.0)
			if hp <= PHASE3_HP_THRESHOLD:
				_begin_phase_transition(Phase.PHASE3)
		return
	if not _scythe_in_hand:
		velocity.x = 0.0
		_state = &"idle_no_scythe"
		return
	var dx := absf(player.global_position.x - global_position.x)
	if _player_imprisoned:
		_state = &"run_slash"
		velocity.x = signf(player.global_position.x - global_position.x) * 260.0
		_set_hitbox_enabled(_run_slash, true)
		if dx < 24.0:
			_player_imprisoned = false
			_set_hitbox_enabled(_run_slash, false)
		return
	if _cd_ready(&"imprison", p3_imprison_cooldown) and _scythe_in_hand:
		_cast_imprison(player)
		return
	if _cd_ready(&"dash", p3_dash_cooldown) and dx > 300.0 and dx <= 500.0:
		_state = &"dash"
		velocity.x = signf(player.global_position.x - global_position.x) * p3_dash_speed
		return
	if _cd_ready(&"combo", p3_combo_cooldown) and dx <= 200.0 and player.global_position.y < global_position.y - 32.0:
		_state = &"combo"
		velocity.x = 0.0
		_set_hitbox_enabled(_attack1, true)
		_set_hitbox_enabled(_attack2, true)
		_set_hitbox_enabled(_attack3, true)
		return
	if _cd_ready(&"kick", p3_kick_cooldown) and dx <= 100.0:
		_state = &"kick"
		velocity.x = 0.0
		_set_hitbox_enabled(_kick_hitbox, true)
		return
	if _cd_ready(&"summon", p3_summon_cooldown) and dx < 500.0:
		_spawn_summon_circle(player)
		return
	if _cd_ready(&"throw_scythe", 2.0):
		_throw_scythe(player)
		return
	_state = &"p3_move"
	velocity.x = signf(player.global_position.x - global_position.x) * p3_move_speed

func _cast_imprison(player: Node2D) -> void:
	_set_cd(&"imprison", p3_imprison_cooldown)
	if _hell_hand_instance and is_instance_valid(_hell_hand_instance):
		return
	var hand := HELL_HAND_SCENE.instantiate()
	hand.global_position = player.global_position
	add_sibling(hand)
	_hell_hand_instance = hand
	hand.call_deferred("setup", self, player, 0.5, 3.0)

func _spawn_summon_circle(player: Node2D) -> void:
	_set_cd(&"summon", p3_summon_cooldown)
	var summon := GHOST_SUMMON_SCENE.instantiate()
	summon.global_position = player.global_position + Vector2(randf_range(-64.0, 64.0), 0.0)
	add_sibling(summon)

func _throw_scythe(player: Node2D) -> void:
	_set_cd(&"throw_scythe", 3.0)
	_scythe_in_hand = false
	var scythe := WITCH_SCYTHE_SCENE.instantiate()
	scythe.global_position = global_position
	add_sibling(scythe)
	_scythe_instance = scythe
	scythe.call_deferred("setup", player, self, p3_scythe_track_interval, p3_scythe_track_count, p3_scythe_fly_speed, p3_scythe_return_speed)

func on_scythe_returned() -> void:
	_scythe_in_hand = true
	_scythe_instance = null

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

func _on_real_hurtbox_area_entered(area: Area2D) -> void:
	if area == null:
		return
	if area.is_in_group("ghost_fist_hitbox"):
		apply_real_damage(1)

func _begin_phase_transition(target_phase: int) -> void:
	if _phase_transitioning or current_phase >= target_phase:
		return
	_phase_transitioning = true
	hp_locked = true
	velocity = Vector2.ZERO
	await get_tree().create_timer(0.6).timeout
	current_phase = target_phase
	if current_phase >= Phase.PHASE2:
		_set_hitbox_enabled(_real_hurtbox, true)
	_phase_transitioning = false
	hp_locked = false

func _begin_death() -> void:
	if _state == &"dead":
		return
	_state = &"dead"
	hp_locked = true
	_clean_spawned_groups()

func _clean_spawned_groups() -> void:
	var groups := ["ghost_tug", "ghost_bomb", "ghost_wraith", "ghost_elite", "witch_scythe", "hell_hand", "ghost_summon"]
	for group_name in groups:
		for n in get_tree().get_nodes_in_group(group_name):
			if is_instance_valid(n):
				n.queue_free()

func _set_hitbox_enabled(area: Area2D, enabled: bool) -> void:
	if area == null:
		return
	area.set_deferred("monitoring", enabled)
	area.set_deferred("monitorable", enabled)

func _cd_ready(key: StringName, sec: float) -> bool:
	var now := Time.get_ticks_msec() / 1000.0
	var until: float = _get_cd(key)
	if now >= until:
		_set_cd(key, sec)
		return true
	return false

func _get_cd(key: StringName) -> float:
	return float(_cooldown_until.get(key, 0.0))

func _set_cd(key: StringName, sec: float) -> void:
	_cooldown_until[key] = Time.get_ticks_msec() / 1000.0 + sec
