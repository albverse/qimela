extends MonsterBase
class_name BossGhostWitch

enum Phase { PHASE1 = 1, PHASE2 = 2, PHASE3 = 3 }
enum BabyState { IN_HUG, THROWN, EXPLODED, REPAIRING, DASHING, SLASHING, RETURNING, HALO }

@export var phase2_hp_threshold: int = 20
@export var phase3_hp_threshold: int = 10
@export var detect_range_px: float = 500.0
@export var slow_move_speed: float = 30.0
@export var baby_throw_speed: float = 600.0
@export var baby_explosion_radius: float = 80.0
@export var baby_repair_duration: float = 2.0
@export var baby_dash_speed: float = 400.0
@export var baby_slash_radius: float = 60.0
@export var start_attack_loop_duration: float = 4.0
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

var current_phase: int = Phase.PHASE1
var baby_state: int = BabyState.IN_HUG
var _phase_transitioning: bool = false
var _battle_started: bool = false
var _baby_realhurtbox_active: bool = false
var _current_anim: StringName = &""
var _current_anim_finished: bool = false
var _current_anim_loop: bool = false
var _current_baby_anim: StringName = &""
var _current_baby_anim_finished: bool = false
var _current_baby_anim_loop: bool = false

@onready var _spine_sprite: Node = $SpineSprite
@onready var _body_box: Area2D = $BodyBox
@onready var _real_hurtbox: Area2D = $RealHurtbox
@onready var _scythe_detect_area: Area2D = $ScytheDetectArea
@onready var _ground_hitbox: Area2D = $GroundHitbox
@onready var _mark_hug: Marker2D = $Mark2D_Hug
@onready var _mark_hale: Marker2D = $Mark2D_Hale
@onready var _baby_statue: Node2D = $BabyStatue
@onready var _baby_spine: Node = $BabyStatue/SpineSprite
@onready var _baby_body_box: Area2D = $BabyStatue/BabyBodyBox
@onready var _baby_real_hurtbox: Area2D = $BabyStatue/BabyRealHurtbox
@onready var _baby_attack_area: Area2D = $BabyStatue/BabyAttackArea
@onready var _baby_explosion_area: Area2D = $BabyStatue/BabyExplosionArea

var _anim_driver: AnimDriverSpine = null
var _baby_anim_driver: AnimDriverSpine = null
var _anim_mock: AnimDriverMock = null
var _baby_anim_mock: AnimDriverMock = null

var _ghost_tug_scene: PackedScene = preload("res://scene/enemies/boss_ghost_witch/GhostTug.tscn")
var _ghost_bomb_scene: PackedScene = preload("res://scene/enemies/boss_ghost_witch/GhostBomb.tscn")
var _ghost_wraith_scene: PackedScene = preload("res://scene/enemies/boss_ghost_witch/GhostWraith.tscn")
var _ghost_elite_scene: PackedScene = preload("res://scene/enemies/boss_ghost_witch/GhostElite.tscn")

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
	_disable_all_hitboxes()
	_enter_phase1()
	if _baby_real_hurtbox:
		_baby_real_hurtbox.area_entered.connect(_on_baby_real_hurtbox_area_entered)
	if _real_hurtbox:
		_real_hurtbox.area_entered.connect(_on_real_hurtbox_area_entered)
	if _spine_sprite and _spine_sprite.has_signal("animation_event"):
		_spine_sprite.animation_event.connect(_on_spine_animation_event)
	if _baby_spine and _baby_spine.has_signal("animation_event"):
		_baby_spine.animation_event.connect(_on_baby_spine_animation_event)

func _physics_process(dt: float) -> void:
	if light_counter > 0.0:
		light_counter = max(light_counter - dt, 0.0)
	_thunder_processed_this_frame = false
	if _anim_mock:
		_anim_mock.tick(dt)
	if _baby_anim_mock:
		_baby_anim_mock.tick(dt)
	_sync_hurtboxes()
	if current_phase == Phase.PHASE1 and baby_state == BabyState.IN_HUG:
		_baby_statue.global_position = _mark_hug.global_position
	if not is_on_floor():
		velocity.y += dt * 1200.0
	else:
		velocity.y = max(velocity.y, 0.0)
	move_and_slide()

func _do_move(_dt: float) -> void:
	pass

func _setup_anim_drivers() -> void:
	if _is_spine_sprite_compatible(_spine_sprite):
		_anim_driver = AnimDriverSpine.new()
		add_child(_anim_driver)
		_anim_driver.setup(_spine_sprite)
		_anim_driver.anim_completed.connect(_on_anim_completed)
	else:
		_anim_mock = AnimDriverMock.new()
		add_child(_anim_mock)
		_anim_mock.anim_completed.connect(_on_anim_completed)
	if _is_spine_sprite_compatible(_baby_spine):
		_baby_anim_driver = AnimDriverSpine.new()
		add_child(_baby_anim_driver)
		_baby_anim_driver.setup(_baby_spine)
		_baby_anim_driver.anim_completed.connect(_on_baby_anim_completed)
	else:
		_baby_anim_mock = AnimDriverMock.new()
		add_child(_baby_anim_mock)
		_baby_anim_mock.anim_completed.connect(_on_baby_anim_completed)

func _is_spine_sprite_compatible(node: Node) -> bool:
	if node == null:
		return false
	if String(node.get_class()) == "SpineSprite":
		return true
	return node.has_method("get_animation_state")

func anim_play(anim_name: StringName, loop: bool, _interruptible: bool = true) -> void:
	if _current_anim == anim_name and _current_anim_loop == loop and not _current_anim_finished:
		return
	_current_anim = anim_name
	_current_anim_loop = loop
	_current_anim_finished = false
	if _anim_driver:
		_anim_driver.play(0, anim_name, loop, AnimDriverSpine.PlayMode.REPLACE_TRACK)
	elif _anim_mock:
		_anim_mock.play(0, anim_name, loop)

func anim_is_finished(anim_name: StringName) -> bool:
	return _current_anim == anim_name and _current_anim_finished

func baby_anim_play(anim_name: StringName, loop: bool) -> void:
	if _current_baby_anim == anim_name and _current_baby_anim_loop == loop and not _current_baby_anim_finished:
		return
	_current_baby_anim = anim_name
	_current_baby_anim_loop = loop
	_current_baby_anim_finished = false
	if _baby_anim_driver:
		_baby_anim_driver.play(0, anim_name, loop, AnimDriverSpine.PlayMode.REPLACE_TRACK)
	elif _baby_anim_mock:
		_baby_anim_mock.play(0, anim_name, loop)

func baby_anim_is_finished(anim_name: StringName) -> bool:
	return _current_baby_anim == anim_name and _current_baby_anim_finished

func _on_anim_completed(_track: int, anim_name: StringName) -> void:
	if anim_name == _current_anim:
		_current_anim_finished = true

func _on_baby_anim_completed(_track: int, anim_name: StringName) -> void:
	if anim_name == _current_baby_anim:
		_current_baby_anim_finished = true

func _set_hitbox_enabled(area: Area2D, enabled: bool) -> void:
	if area == null:
		return
	area.set_deferred("monitoring", enabled)
	area.set_deferred("monitorable", enabled)
	for c in area.get_children():
		if c is CollisionShape2D:
			(c as CollisionShape2D).set_deferred("disabled", not enabled)

func _disable_all_hitboxes() -> void:
	_set_hitbox_enabled(_ground_hitbox, false)
	_set_hitbox_enabled(_real_hurtbox, false)
	_set_hitbox_enabled(_baby_real_hurtbox, false)
	_set_hitbox_enabled(_baby_attack_area, false)
	_set_hitbox_enabled(_baby_explosion_area, false)

func _set_realhurtbox_enabled(enabled: bool) -> void:
	_set_hitbox_enabled(_real_hurtbox, enabled)

func _set_baby_realhurtbox(enabled: bool) -> void:
	_baby_realhurtbox_active = enabled
	_set_hitbox_enabled(_baby_real_hurtbox, enabled)

func _enter_phase1() -> void:
	current_phase = Phase.PHASE1
	baby_state = BabyState.IN_HUG
	_baby_statue.visible = true
	_set_realhurtbox_enabled(false)
	_set_baby_realhurtbox(false)
	anim_play(&"phase1/idle", true)

func _sync_hurtboxes() -> void:
	if current_phase == Phase.PHASE1 and _baby_realhurtbox_active:
		var core_pos := _get_bone_world_position(_baby_anim_driver, "core")
		if core_pos != Vector2.ZERO:
			_baby_real_hurtbox.global_position = core_pos
	elif current_phase >= Phase.PHASE2:
		var hale_pos := _get_bone_world_position(_anim_driver, "hale")
		if hale_pos != Vector2.ZERO:
			_real_hurtbox.global_position = hale_pos

func _get_bone_world_position(driver: AnimDriverSpine, bone_name: String) -> Vector2:
	if driver and driver.has_method("get_bone_world_position"):
		return driver.get_bone_world_position(bone_name)
	return Vector2.ZERO

func apply_real_damage(amount: int) -> void:
	if hp_locked:
		_flash_once()
		return
	hp = max(hp - amount, 0)
	_flash_once()
	anim_play(&"phase1/hurt", false)
	if current_phase == Phase.PHASE1 and hp <= phase2_hp_threshold:
		_begin_phase_transition(Phase.PHASE2)
	elif current_phase == Phase.PHASE2 and hp <= phase3_hp_threshold:
		_begin_phase_transition(Phase.PHASE3)
	elif hp <= 0:
		_on_death()

func apply_hit(hit: HitData) -> bool:
	if hit == null:
		return false
	if hit.weapon_id != &"ghost_fist":
		_flash_once()
		return false
	apply_real_damage(max(1, hit.damage))
	return true

func on_chain_hit(_player: Node, _slot: int) -> int:
	_flash_once()
	return 0

func _begin_phase_transition(target_phase: int) -> void:
	if _phase_transitioning:
		return
	hp_locked = true
	_phase_transitioning = true
	if target_phase == Phase.PHASE2:
		_do_phase1_to_phase2()
	elif target_phase == Phase.PHASE3:
		current_phase = Phase.PHASE3
		_phase_transitioning = false
		hp_locked = false

func _do_phase1_to_phase2() -> void:
	baby_state = BabyState.HALO
	baby_anim_play(&"baby/phase1_to_phase2", false)
	_set_hitbox_enabled(_baby_body_box, false)
	_set_baby_realhurtbox(true)
	_baby_statue.global_position = _mark_hale.global_position
	anim_play(&"phase1/phase1_to_phase2", false)
	await get_tree().create_timer(0.3).timeout
	current_phase = Phase.PHASE2
	_baby_statue.visible = false
	_set_realhurtbox_enabled(true)
	_phase_transitioning = false
	hp_locked = false
	anim_play(&"phase2/idle", true)

func _on_real_hurtbox_area_entered(area: Area2D) -> void:
	if _is_ghostfist_hitbox(area):
		apply_real_damage(1)

func _on_baby_real_hurtbox_area_entered(area: Area2D) -> void:
	if not _baby_realhurtbox_active:
		return
	if _is_ghostfist_hitbox(area):
		apply_real_damage(1)

func _is_ghostfist_hitbox(area: Area2D) -> bool:
	if area == null:
		return false
	if area.is_in_group("ghost_fist_hitbox"):
		return true
	var parent := area.get_parent()
	return parent != null and String(parent.get_script()).find("ghost_fist") >= 0

func _on_spine_animation_event(a1, a2, a3, a4) -> void:
	var e := _extract_event_name(a1, a2, a3, a4)
	match e:
		&"baby_release":
			baby_state = BabyState.THROWN
			baby_anim_play(&"baby/fly", true)
		&"scythe_hitbox_on", &"start_attack_hitbox_on":
			_set_hitbox_enabled(_scythe_detect_area, true)
		&"scythe_hitbox_off", &"start_attack_hitbox_off":
			_set_hitbox_enabled(_scythe_detect_area, false)
		&"realhurtbox_off":
			_set_realhurtbox_enabled(false)
		&"realhurtbox_on":
			_set_realhurtbox_enabled(true)
		&"ground_hitbox_on":
			_set_hitbox_enabled(_ground_hitbox, true)
		&"ground_hitbox_off":
			_set_hitbox_enabled(_ground_hitbox, false)

func _on_baby_spine_animation_event(a1, a2, a3, a4) -> void:
	var e := _extract_event_name(a1, a2, a3, a4)
	match e:
		&"explode_hitbox_on":
			_set_hitbox_enabled(_baby_explosion_area, true)
		&"explode_hitbox_off":
			_set_hitbox_enabled(_baby_explosion_area, false)
		&"realhurtbox_on":
			_set_baby_realhurtbox(true)
		&"realhurtbox_off":
			_set_baby_realhurtbox(false)
		&"dash_hitbox_on", &"slash_hitbox_on":
			_set_hitbox_enabled(_baby_attack_area, true)
		&"dash_hitbox_off", &"slash_hitbox_off":
			_set_hitbox_enabled(_baby_attack_area, false)

func _extract_event_name(a1, a2, a3, a4) -> StringName:
	for a in [a1, a2, a3, a4]:
		if a is Object and a.has_method("get_data"):
			var data = a.get_data()
			if data != null and data.has_method("get_event_name"):
				return StringName(data.get_event_name())
	return &""

func face_toward(target: Node2D) -> void:
	if target == null:
		return
	var dir := signf(target.global_position.x - global_position.x)
	if dir != 0.0:
		scale.x = absf(scale.x) * dir
