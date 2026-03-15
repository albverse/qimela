extends MonsterBase
class_name BossGhostWitch

enum Phase { PHASE1 = 1, PHASE2 = 2, PHASE3 = 3 }
enum BabyState { IN_HUG, THROWN, EXPLODED, REPAIRING, DASHING, POST_DASH_WAIT, WINDING_UP, RETURNING, HALO }

const BT_SUCCESS := 0
const BT_FAILURE := 1
const BT_RUNNING := 2

@export var phase2_hp_threshold: int = 20
@export var phase3_hp_threshold: int = 10

@export var detect_range_px: float = 500.0
@export var slow_move_speed: float = 30.0
@export var baby_throw_speed: float = 600.0
@export var baby_dash_speed: float = 400.0
@export var baby_post_dash_wait: float = 0.7
@export var baby_return_speed: float = 500.0
@export var baby_repair_duration: float = 2.0
@export var start_attack_loop_duration: float = 4.0

@export var scythe_slash_cooldown: float = 1.0
@export var tombstone_drop_cooldown: float = 3.0
@export var undead_wind_cooldown: float = 15.0
@export var ghost_tug_cooldown: float = 5.0
@export var ghost_bomb_interval: float = 5.0

@export var p3_move_speed: float = 120.0
@export var p3_run_speed: float = 250.0
@export var p3_dash_speed: float = 800.0
@export var p3_run_slash_overshoot_px: float = 200.0

var current_phase: int = Phase.PHASE1
var baby_state: int = BabyState.IN_HUG
var _phase_transitioning: bool = false
var _battle_started: bool = false
var _baby_dash_go_triggered: bool = false
var _scythe_in_hand: bool = true
var _scythe_instance: Node2D = null
var _scythe_recall_requested: bool = false
var _player_imprisoned: bool = false

var _current_anim: StringName = &""
var _current_anim_finished: bool = false
var _current_anim_loop: bool = false
var _current_anim_started_sec: float = 0.0

var _current_baby_anim: StringName = &""
var _current_baby_anim_finished: bool = false
var _current_baby_anim_loop: bool = false
var _current_baby_anim_started_sec: float = 0.0

var _bt_start_step: int = 0
var _bt_start_until_sec: float = 0.0
var _bt_throw_target: Node2D = null
var _bt_skill_anim: StringName = &""
var _bt_skill_end_sec: float = 0.0
var _baby_state_until_sec: float = 0.0
var _baby_dash_target_x: float = 0.0

var _anim_driver: AnimDriverSpine = null
var _baby_anim_driver: AnimDriverSpine = null

@onready var _spine_sprite: Node = $SpineSprite
@onready var _real_hurtbox: Area2D = $RealHurtbox
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
	_disable_weak_stun_vanish()
	for hb in [_real_hurtbox, _baby_real_hurtbox, _ground_hitbox, _kick_hitbox, _attack1_area, _attack2_area, _attack3_area, _run_slash_hitbox, _baby_attack_area, _baby_explosion_area]:
		_set_hitbox_enabled(hb, false)

	_setup_anim_drivers()
	if _spine_sprite != null and _spine_sprite.has_signal("animation_event"):
		_spine_sprite.animation_event.connect(_on_spine_event)
	if _baby_spine != null and _baby_spine.has_signal("animation_event"):
		_baby_spine.animation_event.connect(_on_baby_spine_event)

	_baby_statue.global_position = _mark_hug.global_position
	anim_play(&"phase1/idle", true)
	baby_anim_play(&"baby/idle", true)

func _setup_anim_drivers() -> void:
	if _is_spine_sprite_compatible(_spine_sprite):
		_anim_driver = AnimDriverSpine.new()
		add_child(_anim_driver)
		_anim_driver.setup(_spine_sprite)
		_anim_driver.anim_completed.connect(_on_main_anim_completed)
	if _is_spine_sprite_compatible(_baby_spine):
		_baby_anim_driver = AnimDriverSpine.new()
		add_child(_baby_anim_driver)
		_baby_anim_driver.setup(_baby_spine)
		_baby_anim_driver.anim_completed.connect(_on_baby_anim_completed)

func _is_spine_sprite_compatible(node: Node) -> bool:
	if node == null:
		return false
	if String(node.get_class()) == "SpineSprite":
		return true
	return node.has_method("get_animation_state") or node.has_method("getAnimationState")

func _physics_process(_dt: float) -> void:
	super._physics_process(_dt)
	_update_bone_follow()
	_update_damage_hitboxes()
	move_and_slide()

func _do_move(_dt: float) -> void:
	pass

func is_phase_transitioning() -> bool:
	return _phase_transitioning

func is_battle_started() -> bool:
	return _battle_started

func is_baby_in_hug() -> bool:
	return baby_state == BabyState.IN_HUG

func bt_hold_transition() -> void:
	velocity = Vector2.ZERO

func bt_start_battle() -> int:
	if _battle_started:
		return BT_SUCCESS
	var now := Time.get_ticks_msec() / 1000.0
	if _bt_start_step == 0:
		anim_play(&"phase1/start_attack", false)
		_bt_start_step = 1
		return BT_RUNNING
	if _bt_start_step == 1:
		if not anim_is_finished(&"phase1/start_attack"):
			return BT_RUNNING
		anim_play(&"phase1/start_attack_loop", true)
		_bt_start_until_sec = now + start_attack_loop_duration
		_bt_start_step = 2
		return BT_RUNNING
	if _bt_start_step == 2:
		if now < _bt_start_until_sec:
			return BT_RUNNING
		anim_play(&"phase1/start_attack_exter", false)
		_bt_start_step = 3
		return BT_RUNNING
	if _bt_start_step == 3:
		if not anim_is_finished(&"phase1/start_attack_exter"):
			return BT_RUNNING
		_battle_started = true
		_bt_start_step = 0
		return BT_SUCCESS
	return BT_RUNNING

func bt_throw_baby(blackboard: Blackboard) -> int:
	if baby_state != BabyState.IN_HUG:
		return BT_FAILURE
	var actor_id := str(get_instance_id())
	_bt_throw_target = blackboard.get_value("player", null, actor_id)
	if _bt_throw_target == null:
		return BT_FAILURE
	anim_play(&"phase1/throw", false)
	baby_state = BabyState.THROWN
	baby_anim_play(&"baby/spin", true)
	return BT_SUCCESS

func bt_baby_attack_flow() -> int:
	var dt := get_physics_process_delta_time()
	var now := Time.get_ticks_msec() / 1000.0
	var player := _bt_throw_target if _bt_throw_target != null else get_priority_attack_target()

	if baby_state == BabyState.THROWN:
		if player == null:
			return BT_RUNNING
		var dir := (player.global_position - _baby_statue.global_position).normalized()
		_baby_statue.global_position += dir * baby_throw_speed * dt
		if _baby_statue.global_position.distance_to(player.global_position) <= 20.0:
			baby_state = BabyState.EXPLODED
			baby_anim_play(&"baby/explode", false)
			_set_hitbox_enabled(_baby_explosion_area, true)
			_baby_state_until_sec = now + 0.35
		return BT_RUNNING

	if baby_state == BabyState.EXPLODED:
		if now < _baby_state_until_sec and not baby_anim_is_finished(&"baby/explode"):
			return BT_RUNNING
		_set_hitbox_enabled(_baby_explosion_area, false)
		_set_hitbox_enabled(_baby_real_hurtbox, true)
		baby_state = BabyState.REPAIRING
		baby_anim_play(&"baby/repair", false)
		_baby_state_until_sec = now + baby_repair_duration
		return BT_RUNNING

	if baby_state == BabyState.REPAIRING:
		if now < _baby_state_until_sec and not baby_anim_is_finished(&"baby/repair"):
			return BT_RUNNING
		_set_hitbox_enabled(_baby_real_hurtbox, false)
		if _is_player_in_baby_detect_area(player):
			baby_state = BabyState.DASHING
			_baby_dash_go_triggered = false
			_baby_dash_target_x = player.global_position.x
			baby_anim_play(&"baby/dash", false)
			_set_hitbox_enabled(_baby_attack_area, true)
		else:
			baby_state = BabyState.RETURNING
			baby_anim_play(&"baby/return", true)
			_set_hitbox_enabled(_baby_attack_area, false)
		return BT_RUNNING

	if baby_state == BabyState.DASHING:
		if player != null:
			_baby_dash_target_x = player.global_position.x
		var dash_dir := signf(_baby_dash_target_x - _baby_statue.global_position.x)
		_baby_statue.global_position.x += dash_dir * baby_dash_speed * dt
		if absf(_baby_dash_target_x - _baby_statue.global_position.x) < 12.0:
			baby_state = BabyState.POST_DASH_WAIT
			baby_anim_play(&"baby/idle", true)
			_baby_state_until_sec = now + baby_post_dash_wait
		return BT_RUNNING

	if baby_state == BabyState.POST_DASH_WAIT:
		if now < _baby_state_until_sec:
			return BT_RUNNING
		baby_state = BabyState.WINDING_UP
		baby_anim_play(&"baby/wind_up", false)
		return BT_RUNNING

	if baby_state == BabyState.WINDING_UP:
		if not baby_anim_is_finished(&"baby/wind_up"):
			return BT_RUNNING
		baby_state = BabyState.RETURNING
		baby_anim_play(&"baby/return", true)
		return BT_RUNNING

	if baby_state == BabyState.RETURNING:
		var rdir := (_mark_hug.global_position - _baby_statue.global_position).normalized()
		_baby_statue.global_position += rdir * baby_return_speed * dt
		if _baby_statue.global_position.distance_to(_mark_hug.global_position) <= 10.0:
			_set_hitbox_enabled(_baby_attack_area, false)
			baby_state = BabyState.IN_HUG
			_bt_throw_target = null
			anim_play(&"phase1/catch_baby", false)
			baby_anim_play(&"baby/idle", true)
			return BT_SUCCESS
		return BT_RUNNING

	return BT_FAILURE

func _is_player_in_baby_detect_area(player: Node2D) -> bool:
	if player == null:
		return false
	if _baby_detect_area == null:
		return true
	for body in _baby_detect_area.get_overlapping_bodies():
		if body == player:
			return true
	return false

func bt_move_toward_player(speed: float, anim_name: StringName) -> void:
	var player := get_priority_attack_target()
	if player == null:
		velocity = Vector2.ZERO
		return
	velocity.x = signf(player.global_position.x - global_position.x) * speed
	anim_play(anim_name, true)

func bt_cast_phase2_skill(blackboard: Blackboard, cooldown_key: String, cooldown_sec: float, anim_name: StringName) -> int:
	var actor_id := str(get_instance_id())
	var now := Time.get_ticks_msec() / 1000.0
	if _bt_skill_anim == anim_name and now < _bt_skill_end_sec:
		velocity = Vector2.ZERO
		return BT_RUNNING
	if now * 1000.0 < blackboard.get_value(cooldown_key, 0.0, actor_id):
		return BT_FAILURE
	anim_play(anim_name, false)
	_bt_skill_anim = anim_name
	_bt_skill_end_sec = now + 0.8
	blackboard.set_value(cooldown_key, now * 1000.0 + cooldown_sec * 1000.0, actor_id)
	velocity = Vector2.ZERO
	return BT_RUNNING

func bt_spawn_ghost_bomb(blackboard: Blackboard) -> int:
	var actor_id := str(get_instance_id())
	var now_ms := float(Time.get_ticks_msec())
	blackboard.set_value("cd_bomb", now_ms + ghost_bomb_interval * 1000.0, actor_id)
	var scene := load("res://scene/enemies/boss_ghost_witch/GhostBomb.tscn") as PackedScene
	if scene != null:
		var bomb := scene.instantiate()
		if bomb is Node2D:
			(bomb as Node2D).global_position = global_position + Vector2(randf_range(-80.0, 80.0), -20.0)
			get_tree().current_scene.add_child(bomb)
	return BT_SUCCESS

func bt_phase3_combat() -> void:
	var player := get_priority_attack_target()
	if player == null:
		velocity = Vector2.ZERO
		return
	var dx := player.global_position.x - global_position.x
	if not _scythe_in_hand:
		velocity = Vector2.ZERO
		anim_play(&"phase3/idle_no_scythe", true)
		if _scythe_recall_requested and is_instance_valid(_scythe_instance) and _scythe_instance.has_method("recall"):
			_scythe_instance.call("recall", global_position)
			_scythe_recall_requested = false
		return
	if _player_imprisoned:
		anim_play(&"phase3/run_slash", true)
		_set_hitbox_enabled(_run_slash_hitbox, true)
		var target_x := player.global_position.x + signf(dx) * p3_run_slash_overshoot_px
		velocity.x = signf(target_x - global_position.x) * p3_run_speed
		if absf(target_x - global_position.x) < 12.0:
			_player_imprisoned = false
			_set_hitbox_enabled(_run_slash_hitbox, false)
		return
	if absf(dx) <= 100.0:
		anim_play(&"phase3/kick", false)
		velocity = Vector2.ZERO
	else:
		anim_play(&"phase3/walk", true)
		velocity.x = signf(dx) * p3_move_speed
	if absf(dx) > 300.0 and absf(dx) <= 500.0:
		anim_play(&"phase3/dash", true)
		velocity.x = signf(dx) * p3_dash_speed
	if _scythe_instance == null and absf(dx) > 500.0:
		_throw_scythe(player)

func _update_damage_hitboxes() -> void:
	for hb in [_kick_hitbox, _attack1_area, _attack2_area, _attack3_area, _run_slash_hitbox, _ground_hitbox, _baby_attack_area, _baby_explosion_area]:
		if hb == null or not hb.monitoring:
			continue
		for body in hb.get_overlapping_bodies():
			if body != null and body.is_in_group("player") and body.has_method("apply_damage"):
				body.call("apply_damage", 1, hb.global_position)

func _update_bone_follow() -> void:
	if current_phase == Phase.PHASE1:
		if baby_state == BabyState.IN_HUG:
			_baby_statue.global_position = _mark_hug.global_position
		var core := _get_bone_world_position(_baby_anim_driver, "core", _baby_statue.global_position)
		if core != Vector2.ZERO:
			_baby_real_hurtbox.global_position = core
		else:
			_baby_real_hurtbox.global_position = _baby_statue.global_position
	else:
		var hale := _get_bone_world_position(_anim_driver, "hale", _mark_hale.global_position)
		_real_hurtbox.global_position = hale
	if current_phase == Phase.PHASE3:
		_kick_hitbox.global_position = global_position + Vector2(16.0, 0.0)

func _get_bone_world_position(driver: AnimDriverSpine, bone_name: String, fallback: Vector2) -> Vector2:
	if driver == null:
		return fallback
	var p := driver.get_bone_world_position(bone_name)
	if p == Vector2.ZERO:
		return fallback
	return p

func _throw_scythe(player: Node2D) -> void:
	if not _scythe_in_hand:
		return
	anim_play(&"phase3/throw_scythe", false)
	var scene := load("res://scene/enemies/boss_ghost_witch/WitchScythe.tscn") as PackedScene
	if scene == null:
		return
	_scythe_instance = scene.instantiate() as Node2D
	if _scythe_instance == null:
		return
	get_tree().current_scene.add_child(_scythe_instance)
	_scythe_instance.global_position = global_position
	if _scythe_instance.has_method("setup"):
		_scythe_instance.call("setup", player, self, 1.0, 3, 300.0, 500.0)
	_scythe_in_hand = false

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
	_current_anim_started_sec = Time.get_ticks_msec() / 1000.0
	if _anim_driver != null:
		_anim_driver.play(0, anim_name, loop, AnimDriverSpine.PlayMode.REPLACE_TRACK)
	elif _spine_sprite != null and _spine_sprite.has_method("set_animation"):
		_spine_sprite.call("set_animation", String(anim_name), loop, 0)

func baby_anim_play(anim_name: StringName, loop: bool) -> void:
	if _current_baby_anim == anim_name and not _current_baby_anim_finished and _current_baby_anim_loop == loop:
		return
	_current_baby_anim = anim_name
	_current_baby_anim_finished = false
	_current_baby_anim_loop = loop
	_current_baby_anim_started_sec = Time.get_ticks_msec() / 1000.0
	if _baby_anim_driver != null:
		_baby_anim_driver.play(0, anim_name, loop, AnimDriverSpine.PlayMode.REPLACE_TRACK)
	elif _baby_spine != null and _baby_spine.has_method("set_animation"):
		_baby_spine.call("set_animation", String(anim_name), loop, 0)

func anim_is_finished(anim_name: StringName) -> bool:
	if _current_anim != anim_name:
		return false
	if _current_anim_finished:
		return true
	if not _current_anim_loop and Time.get_ticks_msec() / 1000.0 - _current_anim_started_sec > 0.9:
		return true
	return false

func baby_anim_is_finished(anim_name: StringName) -> bool:
	if _current_baby_anim != anim_name:
		return false
	if _current_baby_anim_finished:
		return true
	if not _current_baby_anim_loop and Time.get_ticks_msec() / 1000.0 - _current_baby_anim_started_sec > 0.9:
		return true
	return false

func _on_main_anim_completed(_track: int, anim_name: StringName) -> void:
	if anim_name == _current_anim:
		_current_anim_finished = true

func _on_baby_anim_completed(_track: int, anim_name: StringName) -> void:
	if anim_name == _current_baby_anim:
		_current_baby_anim_finished = true

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
		&"slash_hitbox_on": _set_hitbox_enabled(_run_slash_hitbox, true)
		&"slash_hitbox_off": _set_hitbox_enabled(_run_slash_hitbox, false)
		&"ground_hitbox_on": _set_hitbox_enabled(_ground_hitbox, true)
		&"ground_hitbox_off": _set_hitbox_enabled(_ground_hitbox, false)
		&"death_finished": anim_play(&"phase3/death_loop", true)

func _on_baby_spine_event(a1 = null, a2 = null, a3 = null, a4 = null) -> void:
	var e := _extract_event_name(a1, a2, a3, a4)
	match e:
		&"dash_go": _baby_dash_go_triggered = true
		&"dash_hitbox_on": _set_hitbox_enabled(_baby_attack_area, true)
		&"dash_hitbox_off": _set_hitbox_enabled(_baby_attack_area, false)
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

func _disable_weak_stun_vanish() -> void:
	weak_stun_time = 0.0
	weak_stun_extend_time = 0.0
	stun_duration = 0.0
