extends MonsterBase
class_name BossGhostWitch

enum Phase { PHASE1 = 1, PHASE2 = 2, PHASE3 = 3 }
enum BabyState { IN_HUG = 0, THROWN = 1, RETURNING = 2, HALO = 3 }

@export var phase2_hp_threshold: int = 20
@export var phase3_hp_threshold: int = 10
@export var move_speed_p1: float = 70.0
@export var move_speed_p2: float = 90.0
@export var move_speed_p3: float = 130.0
@export var melee_range: float = 140.0
@export var dash_range: float = 260.0
@export var start_attack_loop_duration: float = 4.0

@export var baby_throw_speed: float = 320.0
@export var baby_return_speed: float = 380.0
@export var baby_dash_speed: float = 560.0
@export var baby_dash_hit_damage: int = 1

var current_phase: int = Phase.PHASE1
var baby_state: int = BabyState.IN_HUG
var hp_locked: bool = false
var _phase_transitioning: bool = false
var _battle_started: bool = false

var _anim_driver: AnimDriverSpine = null
var _anim_mock: AnimDriverMock = null
var _current_anim: StringName = &""
var _current_anim_finished: bool = false

var _baby_velocity: Vector2 = Vector2.ZERO
var _baby_target: Node2D = null
var _scythe_in_hand: bool = true
var _scythe_recall_requested: bool = false

@onready var _spine_sprite: Node = get_node_or_null("SpineSprite")
@onready var _body_box: Area2D = get_node_or_null("BodyBox") as Area2D
@onready var _real_hurtbox: Area2D = get_node_or_null("RealHurtbox") as Area2D
@onready var _scythe_detect_area: Area2D = get_node_or_null("ScytheDetectArea") as Area2D
@onready var _ground_hitbox: Area2D = get_node_or_null("GroundHitbox") as Area2D
@onready var _mark_hug: Marker2D = get_node_or_null("Mark2D_Hug") as Marker2D
@onready var _mark_halo: Marker2D = get_node_or_null("Mark2D_Hale") as Marker2D

@onready var _baby_root: Node2D = get_node_or_null("BabyStatue") as Node2D
@onready var _baby_spine: Node = get_node_or_null("BabyStatue/SpineSprite")
@onready var _baby_real_hurtbox: Area2D = get_node_or_null("BabyStatue/BabyRealHurtbox") as Area2D
@onready var _baby_attack_area: Area2D = get_node_or_null("BabyStatue/BabyAttackArea") as Area2D
@onready var _baby_explosion_area: Area2D = get_node_or_null("BabyStatue/BabyExplosionArea") as Area2D
@onready var _baby_detect_area: Area2D = get_node_or_null("BabyStatue/BabyDetectArea") as Area2D

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

	_setup_anim_driver()
	_set_realhurtbox_enabled(false)
	_set_hitbox_enabled(_ground_hitbox, false)
	_set_hitbox_enabled(_baby_real_hurtbox, false)
	_set_hitbox_enabled(_baby_attack_area, false)
	_set_hitbox_enabled(_baby_explosion_area, false)
	if _baby_root and _mark_hug:
		_baby_root.global_position = _mark_hug.global_position
	anim_play(&"phase1/idle", true)

func _setup_anim_driver() -> void:
	if _spine_sprite and String(_spine_sprite.get_class()) == "SpineSprite":
		_anim_driver = AnimDriverSpine.new()
		add_child(_anim_driver)
		_anim_driver.setup(_spine_sprite)
		_anim_driver.anim_completed.connect(_on_anim_completed)
	else:
		_anim_mock = AnimDriverMock.new()
		add_child(_anim_mock)
		_anim_mock.anim_completed.connect(_on_anim_completed)

func _physics_process(dt: float) -> void:
	super._physics_process(dt)
	if _anim_mock:
		_anim_mock.tick(dt)
	_sync_attachment_points()
	_tick_baby_flight(dt)

func _do_move(_dt: float) -> void:
	if hp <= 0 or _phase_transitioning:
		velocity = Vector2.ZERO
		move_and_slide()
		return
	if not _battle_started:
		velocity = Vector2.ZERO
		move_and_slide()
		return
	var player := get_priority_attack_target()
	if player == null:
		velocity = Vector2.ZERO
		move_and_slide()
		return
	var to_player := player.global_position - global_position
	var dist := to_player.length()
	if dist <= melee_range:
		velocity = Vector2.ZERO
		anim_play(_phase_anim(&"idle"), true)
	else:
		velocity = to_player.normalized() * _current_move_speed()
		anim_play(_phase_anim(&"move"), true)
	move_and_slide()

func ai_tick(_dt: float) -> void:
	if hp <= 0:
		return
	if not _battle_started:
		if _any_player_in_area("DetectArea500"):
			_start_battle_flow()
		return
	if _phase_transitioning:
		return
	if current_phase == Phase.PHASE1:
		_try_phase1_attack()
	elif current_phase == Phase.PHASE2:
		_try_phase2_attack()
	else:
		_try_phase3_attack()

func _try_phase1_attack() -> void:
	if baby_state == BabyState.IN_HUG and _is_cd_ready("cd_baby_throw"):
		_baby_throw_start()
		_set_cd("cd_baby_throw", 4.0)

func _try_phase2_attack() -> void:
	if _is_cd_ready("cd_bomb"):
		_spawn_ghost_bomb()
		_set_cd("cd_bomb", 3.5)
	if _is_cd_ready("cd_wraith"):
		_spawn_wraith(false)
		_set_cd("cd_wraith", 5.0)

func _try_phase3_attack() -> void:
	var player := get_priority_attack_target()
	if player == null:
		return
	if global_position.distance_to(player.global_position) >= dash_range and _is_cd_ready("cd_dash"):
		anim_play(&"phase3/dash", false)
		_set_cd("cd_dash", 10.0)
	elif _is_cd_ready("cd_combo"):
		anim_play(&"phase3/combo", false)
		_set_cd("cd_combo", 1.0)

func _start_battle_flow() -> void:
	_battle_started = true
	anim_play(&"phase1/start_attack", false)

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

func apply_real_damage(amount: int) -> void:
	if hp_locked or amount <= 0:
		_flash_once()
		return
	hp = max(hp - amount, 0)
	_flash_once()
	if current_phase == Phase.PHASE3 and not _scythe_in_hand:
		_scythe_recall_requested = true
	if current_phase == Phase.PHASE1 and hp <= phase2_hp_threshold:
		_begin_phase_transition(Phase.PHASE2)
	elif current_phase == Phase.PHASE2 and hp <= phase3_hp_threshold:
		_begin_phase_transition(Phase.PHASE3)
	elif hp <= 0:
		_begin_death()

func _begin_phase_transition(next_phase: int) -> void:
	if _phase_transitioning:
		return
	hp_locked = true
	_phase_transitioning = true
	velocity = Vector2.ZERO
	move_and_slide()
	if next_phase == Phase.PHASE2:
		anim_play(&"phase1/to_phase2", false)
		current_phase = Phase.PHASE2
		baby_state = BabyState.HALO
		_set_realhurtbox_enabled(true)
	elif next_phase == Phase.PHASE3:
		anim_play(&"phase2/to_phase3", false)
		current_phase = Phase.PHASE3
		_set_realhurtbox_enabled(true)
	await get_tree().create_timer(1.0).timeout
	hp_locked = false
	_phase_transitioning = false
	anim_play(_phase_anim(&"idle"), true)

func _begin_death() -> void:
	hp_locked = true
	velocity = Vector2.ZERO
	anim_play(_phase_anim(&"death"), false)
	await get_tree().create_timer(1.2).timeout
	queue_free()

func _sync_attachment_points() -> void:
	if _baby_root == null:
		return
	if baby_state == BabyState.IN_HUG and _mark_hug:
		_baby_root.global_position = _mark_hug.global_position
	elif baby_state == BabyState.HALO and _mark_halo:
		_baby_root.global_position = _mark_halo.global_position

func _baby_throw_start() -> void:
	var player := get_priority_attack_target()
	if player == null or _baby_root == null:
		return
	baby_state = BabyState.THROWN
	_baby_target = player
	_set_hitbox_enabled(_baby_attack_area, true)
	_baby_velocity = (player.global_position - _baby_root.global_position).normalized() * baby_throw_speed

func _tick_baby_flight(dt: float) -> void:
	if _baby_root == null:
		return
	if baby_state == BabyState.THROWN:
		_baby_root.global_position += _baby_velocity * dt
		if _baby_target and is_instance_valid(_baby_target):
			var dist := _baby_root.global_position.distance_to(_baby_target.global_position)
			if dist <= 60.0:
				_set_hitbox_enabled(_baby_attack_area, false)
				baby_state = BabyState.RETURNING
				_baby_velocity = (_mark_hug.global_position - _baby_root.global_position).normalized() * baby_return_speed
	elif baby_state == BabyState.RETURNING:
		_baby_root.global_position += _baby_velocity * dt
		if _mark_hug and _baby_root.global_position.distance_to(_mark_hug.global_position) <= 20.0:
			baby_state = BabyState.IN_HUG
			_set_hitbox_enabled(_baby_attack_area, false)

func _spawn_ghost_bomb() -> void:
	if _ghost_bomb_scene == null or get_parent() == null:
		return
	var bomb := _ghost_bomb_scene.instantiate() as Node2D
	if bomb == null:
		return
	bomb.global_position = global_position
	if bomb.has_method("setup"):
		bomb.call("setup", get_priority_attack_target(), 2.0)
	get_parent().add_child(bomb)

func _spawn_wraith(spawn_elite: bool) -> void:
	var scene := _ghost_elite_scene if spawn_elite else _ghost_wraith_scene
	if scene == null or get_parent() == null:
		return
	var inst := scene.instantiate() as Node2D
	if inst == null:
		return
	inst.global_position = global_position
	if inst.has_method("setup"):
		inst.call("setup", 1, get_priority_attack_target(), global_position)
	get_parent().add_child(inst)

func _phase_anim(name: StringName) -> StringName:
	if current_phase == Phase.PHASE1:
		return StringName("phase1/%s" % String(name))
	if current_phase == Phase.PHASE2:
		return StringName("phase2/%s" % String(name))
	return StringName("phase3/%s" % String(name))

func _current_move_speed() -> float:
	if current_phase == Phase.PHASE1:
		return move_speed_p1
	if current_phase == Phase.PHASE2:
		return move_speed_p2
	return move_speed_p3

func _set_cd(key: StringName, sec: float) -> void:
	set_meta(key, Time.get_ticks_msec() / 1000.0 + sec)

func _is_cd_ready(key: StringName) -> bool:
	var now := Time.get_ticks_msec() / 1000.0
	return now >= float(get_meta(key, 0.0))

func _any_player_in_area(area_name: String) -> bool:
	var area := get_node_or_null(area_name) as Area2D
	if area == null:
		return false
	for body in area.get_overlapping_bodies():
		if body and body.is_in_group("player"):
			return true
	return false

func _set_realhurtbox_enabled(enabled: bool) -> void:
	_set_hitbox_enabled(_real_hurtbox, enabled)
	_set_hitbox_enabled(_baby_real_hurtbox, enabled and baby_state != BabyState.HALO)

func _set_hitbox_enabled(area: Area2D, enabled: bool) -> void:
	if area == null:
		return
	area.monitoring = enabled
	area.monitorable = enabled
	for c in area.get_children():
		var shape := c as CollisionShape2D
		if shape:
			shape.disabled = not enabled

func anim_play(anim_name: StringName, loop: bool, _interruptible: bool = true) -> void:
	if _current_anim == anim_name and not _current_anim_finished:
		return
	_current_anim = anim_name
	_current_anim_finished = false
	if _anim_driver:
		_anim_driver.play(anim_name, loop)
	elif _anim_mock:
		_anim_mock.play(anim_name, loop)

func anim_is_finished(anim_name: StringName) -> bool:
	if _current_anim != anim_name:
		return false
	return _current_anim_finished

func _on_anim_completed(_track: int, anim_name: StringName) -> void:
	if anim_name == _current_anim:
		_current_anim_finished = true
