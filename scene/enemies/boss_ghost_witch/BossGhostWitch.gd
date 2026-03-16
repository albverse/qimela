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
var _scythe_in_hand: bool = true
var _scythe_instance: Node2D = null
var _scythe_recall_requested: bool = false
var _hell_hand_instance: Node2D = null
var _player_imprisoned: bool = false

var _current_anim: StringName = &""
var _current_anim_finished: bool = false
var _current_anim_loop: bool = false

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
	floor_snap_length = 0.0
	super._ready()
	add_to_group("boss_ghost_witch")
	_disable_weak_stun_vanish()
	_set_hitbox_enabled(_real_hurtbox, false)
	_set_hitbox_enabled(_baby_real_hurtbox, false)
	_set_hitbox_enabled(_ground_hitbox, false)
	_set_hitbox_enabled(_kick_hitbox, false)
	_set_hitbox_enabled(_attack1_area, false)
	_set_hitbox_enabled(_attack2_area, false)
	_set_hitbox_enabled(_attack3_area, false)
	_set_hitbox_enabled(_run_slash_hitbox, false)
	if _spine_sprite != null and _spine_sprite.has_signal("animation_event"):
		_spine_sprite.animation_event.connect(_on_spine_event)
	if _baby_spine != null and _baby_spine.has_signal("animation_event"):
		_baby_spine.animation_event.connect(_on_baby_spine_event)
	anim_play(&"phase1/idle", true)

func _physics_process(dt: float) -> void:
	super._physics_process(dt)
	_update_bone_follow()
	_update_halo_baby()
	move_and_slide()

func _do_move(_dt: float) -> void:
	pass

func _update_halo_baby() -> void:
	if baby_state == BabyState.HALO:
		_baby_statue.global_position = _mark_hale.global_position

func _update_damage_hitboxes() -> void:
	for hb in [_kick_hitbox, _attack1_area, _attack2_area, _attack3_area, _run_slash_hitbox, _ground_hitbox, _baby_attack_area, _baby_explosion_area]:
		if hb == null:
			continue
		for body in hb.get_overlapping_bodies():
			if body != null and body.is_in_group("player") and body.has_method("apply_damage"):
				body.call("apply_damage", 1, hb.global_position)

func _update_bone_follow() -> void:
	if current_phase == Phase.PHASE1:
		_baby_real_hurtbox.global_position = _baby_statue.global_position
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

func anim_play(anim_name: StringName, loop: bool, _interruptible: bool = true) -> void:
	if _current_anim == anim_name and not _current_anim_finished and _current_anim_loop == loop:
		return
	_current_anim = anim_name
	_current_anim_finished = false
	_current_anim_loop = loop
	if _spine_sprite != null and _spine_sprite.has_method("set_animation"):
		_spine_sprite.call("set_animation", anim_name, loop)

func baby_anim_play(anim_name: StringName, loop: bool) -> void:
	if _baby_spine != null and _baby_spine.has_method("set_animation"):
		_baby_spine.call("set_animation", anim_name, loop)

func anim_is_finished(anim_name: StringName) -> bool:
	return _current_anim == anim_name and _current_anim_finished

func _on_spine_event(a1 = null, a2 = null, a3 = null, a4 = null) -> void:
	var e := _extract_event_name(a1, a2, a3, a4)
	match e:
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
		&"ground_hitbox_on": _set_hitbox_enabled(_ground_hitbox, true)
		&"ground_hitbox_off": _set_hitbox_enabled(_ground_hitbox, false)
		&"death_finished": anim_play(&"phase3/death_loop", true)

func _on_baby_spine_event(a1 = null, a2 = null, a3 = null, a4 = null) -> void:
	var e := _extract_event_name(a1, a2, a3, a4)
	match e:
		&"dash_go": _baby_dash_go_triggered = true
		&"dash_hitbox_on": _set_hitbox_enabled(_baby_attack_area, true)
		&"explode_hitbox_on": _set_hitbox_enabled(_baby_explosion_area, true)
		&"explode_hitbox_off": _set_hitbox_enabled(_baby_explosion_area, false)
		&"realhurtbox_on": _set_hitbox_enabled(_baby_real_hurtbox, true)
		&"realhurtbox_off": _set_hitbox_enabled(_baby_real_hurtbox, false)

func _extract_event_name(a1 = null, a2 = null, a3 = null, a4 = null) -> StringName:
	for v in [a4, a3, a2, a1]:
		if v is StringName and StringName(v) != &"":
			return v
		if v is String and String(v) != "":
			return StringName(v)
	return &""

func face_toward(target: Node2D) -> void:
	if target == null:
		return
	var dx := target.global_position.x - global_position.x
	if absf(dx) < 2.0:
		return
	if _spine_sprite != null:
		_spine_sprite.scale.x = absf(_spine_sprite.scale.x) * (1.0 if dx > 0.0 else -1.0)

func baby_anim_is_finished(anim_name: StringName) -> bool:
	if _baby_spine == null or not _baby_spine.has_method("get_current_animation"):
		return true
	return _baby_spine.call("get_current_animation") == anim_name

func _close_all_combo_hitboxes() -> void:
	_set_hitbox_enabled(_attack1_area, false)
	_set_hitbox_enabled(_attack2_area, false)
	_set_hitbox_enabled(_attack3_area, false)

func _set_baby_realhurtbox(enabled: bool) -> void:
	_set_hitbox_enabled(_baby_real_hurtbox, enabled)

func _set_realhurtbox_enabled(enabled: bool) -> void:
	_set_hitbox_enabled(_real_hurtbox, enabled)

func _disable_weak_stun_vanish() -> void:
	weak_stun_time = 0.0
	weak_stun_extend_time = 0.0
	stun_duration = 0.0

func _exit_tree() -> void:
	if _player_imprisoned:
		var p := get_priority_attack_target()
		if p != null and p.has_method("set_external_control_frozen"):
			p.call("set_external_control_frozen", false)
