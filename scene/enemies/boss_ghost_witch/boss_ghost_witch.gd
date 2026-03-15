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

@export var scythe_slash_cooldown: float = 1.0
@export var tombstone_drop_cooldown: float = 3.0
@export var undead_wind_cooldown: float = 15.0
@export var ghost_tug_cooldown: float = 5.0
@export var ghost_bomb_interval: float = 5.0
@export var ghost_bomb_max_count: int = 3

@export var p3_cast_imprison_cooldown: float = 10.0
@export var p3_dash_cooldown: float = 10.0
@export var p3_combo_cooldown: float = 1.0
@export var p3_kick_cooldown: float = 1.0
@export var p3_summon_cooldown: float = 8.0

var current_phase: int = Phase.PHASE1
var baby_state: int = BabyState.IN_HUG
var _phase_transitioning: bool = false
var _battle_started: bool = false
var _baby_realhurtbox_active: bool = false
var _baby_dash_go_triggered: bool = false

var _scythe_in_hand: bool = true
var _scythe_recall_requested: bool = false
var _player_imprisoned: bool = false

var _current_anim: StringName = &""
var _anim_end_ms: int = 0
var _current_baby_anim: StringName = &""
var _baby_anim_end_ms: int = 0

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
@onready var _kick_hitbox: Area2D = $KickHitbox

var _ghost_tug_scene: PackedScene = preload("res://scene/enemies/boss_ghost_witch/GhostTug.tscn")
var _ghost_bomb_scene: PackedScene = preload("res://scene/enemies/boss_ghost_witch/GhostBomb.tscn")
var _ghost_wraith_scene: PackedScene = preload("res://scene/enemies/boss_ghost_witch/GhostWraith.tscn")
var _ghost_elite_scene: PackedScene = preload("res://scene/enemies/boss_ghost_witch/GhostElite.tscn")
var _witch_scythe_scene: PackedScene = preload("res://scene/enemies/boss_ghost_witch/WitchScythe.tscn")
var _hell_hand_scene: PackedScene = preload("res://scene/enemies/boss_ghost_witch/HellHand.tscn")
var _ghost_summon_scene: PackedScene = preload("res://scene/enemies/boss_ghost_witch/GhostSummon.tscn")

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
	_baby_real_hurtbox.area_entered.connect(_on_baby_real_hurtbox_area_entered)
	_real_hurtbox.area_entered.connect(_on_real_hurtbox_area_entered)

func _physics_process(dt: float) -> void:
	if light_counter > 0.0:
		light_counter = max(light_counter - dt, 0.0)
	_sync_hurtboxes()
	if current_phase == Phase.PHASE1 and baby_state == BabyState.IN_HUG:
		_baby_statue.global_position = _mark_hug.global_position
	if not is_on_floor():
		velocity.y += dt * 1200.0
	else:
		velocity.y = max(velocity.y, 0.0)
	move_and_slide()

func _enter_phase1() -> void:
	current_phase = Phase.PHASE1
	baby_state = BabyState.IN_HUG
	hp_locked = false
	_baby_statue.visible = true
	_set_baby_realhurtbox(false)
	_set_hitbox_enabled(_real_hurtbox, false)
	anim_play(&"phase1/idle", true)
	baby_anim_play(&"baby/idle", true)

func _enter_phase2() -> void:
	current_phase = Phase.PHASE2
	baby_state = BabyState.HALO
	_baby_statue.visible = false
	_set_hitbox_enabled(_real_hurtbox, true)
	_set_baby_realhurtbox(false)
	anim_play(&"phase2/idle", true)

func _enter_phase3() -> void:
	current_phase = Phase.PHASE3
	_scythe_in_hand = true
	_player_imprisoned = false
	anim_play(&"phase3/idle", true)

func _sync_hurtboxes() -> void:
	match current_phase:
		Phase.PHASE1:
			if _baby_realhurtbox_active:
				_baby_real_hurtbox.global_position = _baby_statue.global_position
		Phase.PHASE2, Phase.PHASE3:
			_real_hurtbox.global_position = _mark_hale.global_position
	if current_phase == Phase.PHASE3:
		_kick_hitbox.global_position = global_position + Vector2(24.0 * signf(scale.x), 0)

func apply_real_damage(amount: int) -> void:
	if hp_locked:
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

func _begin_phase_transition(next_phase: int) -> void:
	if _phase_transitioning:
		return
	_phase_transitioning = true
	hp_locked = true
	if next_phase == Phase.PHASE2:
		anim_play(&"phase1/phase1_to_phase2", false)
	elif next_phase == Phase.PHASE3:
		anim_play(&"phase2/phase2_to_phase3", false)
	await get_tree().create_timer(1.0).timeout
	if next_phase == Phase.PHASE2:
		_enter_phase2()
	else:
		_enter_phase3()
	hp_locked = false
	_phase_transitioning = false

func _begin_death() -> void:
	hp_locked = true
	velocity = Vector2.ZERO
	anim_play(&"phase3/death", false)
	await get_tree().create_timer(1.5).timeout
	queue_free()

func _disable_all_hitboxes() -> void:
	_set_hitbox_enabled(_real_hurtbox, false)
	_set_hitbox_enabled(_ground_hitbox, false)
	_set_hitbox_enabled(_baby_attack_area, false)
	_set_hitbox_enabled(_baby_explosion_area, false)
	_set_hitbox_enabled(_baby_real_hurtbox, false)
	_set_hitbox_enabled(_kick_hitbox, false)

func _set_hitbox_enabled(area: Area2D, enabled: bool) -> void:
	if area == null:
		return
	area.monitoring = enabled
	area.monitorable = enabled
	for c in area.get_children():
		if c is CollisionShape2D:
			(c as CollisionShape2D).set_deferred("disabled", not enabled)

func _set_baby_realhurtbox(active: bool) -> void:
	_baby_realhurtbox_active = active
	_set_hitbox_enabled(_baby_real_hurtbox, active)

func _on_real_hurtbox_area_entered(area: Area2D) -> void:
	if _is_ghostfist_hitbox(area):
		apply_real_damage(1)

func _on_baby_real_hurtbox_area_entered(area: Area2D) -> void:
	if _is_ghostfist_hitbox(area) and _baby_realhurtbox_active:
		apply_real_damage(1)

func _is_ghostfist_hitbox(area: Area2D) -> bool:
	if area == null:
		return false
	if area.is_in_group("ghost_fist_hitbox"):
		return true
	var p := area.get_parent()
	if p != null and p.is_in_group("ghost_fist"):
		return true
	return false

func anim_play(anim_name: StringName, loop: bool = true) -> void:
	_current_anim = anim_name
	if loop:
		_anim_end_ms = 0
	else:
		_anim_end_ms = Time.get_ticks_msec() + 700

func anim_is_finished(anim_name: StringName) -> bool:
	if _current_anim != anim_name:
		return false
	if _anim_end_ms == 0:
		return false
	return Time.get_ticks_msec() >= _anim_end_ms

func baby_anim_play(anim_name: StringName, loop: bool = true) -> void:
	_current_baby_anim = anim_name
	if loop:
		_baby_anim_end_ms = 0
	else:
		_baby_anim_end_ms = Time.get_ticks_msec() + 500

func baby_anim_is_finished(anim_name: StringName) -> bool:
	if _current_baby_anim != anim_name:
		return false
	if _baby_anim_end_ms == 0:
		return false
	return Time.get_ticks_msec() >= _baby_anim_end_ms

func is_player_in_range(range_px: float) -> bool:
	var player := get_priority_attack_target()
	if player == null:
		return false
	return abs(player.global_position.x - global_position.x) <= range_px

func is_player_on_ground() -> bool:
	var p := get_priority_attack_target()
	if p == null:
		return false
	if p.has_method("is_on_floor"):
		return bool(p.call("is_on_floor"))
	return true

func is_player_on_platform() -> bool:
	var p := get_priority_attack_target()
	if p == null:
		return false
	return p.global_position.y < global_position.y - 40.0

func is_player_above_boss() -> bool:
	var p := get_priority_attack_target()
	if p == null:
		return false
	return p.global_position.y < global_position.y - 20.0

func set_skill_cooldown(blackboard: Blackboard, key: String, sec: float) -> void:
	var actor_id := str(get_instance_id())
	blackboard.set_value(key, Time.get_ticks_msec() + sec * 1000.0, actor_id)

func spawn_ghost_bomb() -> void:
	var n := _ghost_bomb_scene.instantiate()
	n.global_position = global_position + Vector2(randf_range(-100, 100), -20)
	get_tree().current_scene.add_child(n)

func spawn_ghost_tug() -> void:
	var n := _ghost_tug_scene.instantiate()
	n.global_position = global_position + Vector2(signf(scale.x) * 180.0, 0)
	get_tree().current_scene.add_child(n)

func spawn_undead_wave() -> void:
	for i in range(3):
		var n := _ghost_wraith_scene.instantiate()
		n.global_position = global_position + Vector2(-120 + i * 120, -30)
		get_tree().current_scene.add_child(n)

func spawn_hell_hand() -> void:
	var n := _hell_hand_scene.instantiate()
	n.global_position = get_priority_attack_target().global_position if get_priority_attack_target() else global_position
	get_tree().current_scene.add_child(n)
	_player_imprisoned = true

func spawn_summon_ghost() -> void:
	var n := _ghost_summon_scene.instantiate()
	n.global_position = get_priority_attack_target().global_position if get_priority_attack_target() else global_position
	get_tree().current_scene.add_child(n)

func throw_scythe() -> void:
	if not _scythe_in_hand:
		return
	_scythe_in_hand = false
	var scy := _witch_scythe_scene.instantiate()
	scy.global_position = global_position
	if scy.has_method("bind_owner"):
		scy.bind_owner(self)
	get_tree().current_scene.add_child(scy)

func recall_scythe() -> void:
	_scythe_in_hand = true
	_scythe_recall_requested = false

func bt_wait_transition(_bb: Blackboard) -> int:
	return BeehaveNode.RUNNING if _phase_transitioning else BeehaveNode.SUCCESS

func bt_act_start_battle(_bb: Blackboard) -> int:
	if _battle_started:
		return BeehaveNode.SUCCESS
	anim_play(&"phase1/start_attack", false)
	if anim_is_finished(&"phase1/start_attack"):
		anim_play(&"phase1/start_attack_loop", true)
		_battle_started = true
	return BeehaveNode.RUNNING

func bt_act_throw_baby(_bb: Blackboard) -> int:
	if baby_state != BabyState.IN_HUG:
		return BeehaveNode.SUCCESS
	baby_state = BabyState.THROWN
	baby_anim_play(&"baby/spin", true)
	return BeehaveNode.SUCCESS

func bt_act_baby_attack_flow(_bb: Blackboard) -> int:
	if baby_state == BabyState.THROWN:
		baby_state = BabyState.EXPLODED
		_set_baby_realhurtbox(true)
		return BeehaveNode.RUNNING
	if baby_state == BabyState.EXPLODED:
		baby_state = BabyState.REPAIRING
		return BeehaveNode.RUNNING
	if baby_state == BabyState.REPAIRING:
		if is_player_in_range(180.0):
			baby_state = BabyState.DASHING
		else:
			baby_state = BabyState.WINDING_UP
		return BeehaveNode.RUNNING
	if baby_state == BabyState.DASHING:
		baby_state = BabyState.RETURNING
		return BeehaveNode.RUNNING
	if baby_state == BabyState.RETURNING:
		baby_state = BabyState.IN_HUG
		_set_baby_realhurtbox(false)
		return BeehaveNode.SUCCESS
	return BeehaveNode.RUNNING

func bt_act_slow_move_to_player(_bb: Blackboard) -> int:
	var p := get_priority_attack_target()
	if p == null:
		velocity.x = 0
		return BeehaveNode.RUNNING
	var d := p.global_position.x - global_position.x
	if abs(d) < 20:
		velocity.x = 0
		anim_play(&"phase1/idle", true)
	else:
		velocity.x = signf(d) * slow_move_speed
		anim_play(&"phase1/walk", true)
	return BeehaveNode.RUNNING

func bt_act_scythe_slash(bb: Blackboard) -> int:
	anim_play(&"phase2/scythe_slash", false)
	set_skill_cooldown(bb, "cd_scythe", scythe_slash_cooldown)
	return BeehaveNode.SUCCESS

func bt_act_tombstone_drop(bb: Blackboard) -> int:
	anim_play(&"phase2/tombstone", false)
	set_skill_cooldown(bb, "cd_tombstone", tombstone_drop_cooldown)
	return BeehaveNode.SUCCESS

func bt_act_undead_wind(bb: Blackboard) -> int:
	anim_play(&"phase2/undead_wind", false)
	spawn_undead_wave()
	set_skill_cooldown(bb, "cd_wind", undead_wind_cooldown)
	return BeehaveNode.SUCCESS

func bt_act_ghost_tug(bb: Blackboard) -> int:
	anim_play(&"phase2/ghost_tug", false)
	spawn_ghost_tug()
	set_skill_cooldown(bb, "cd_tug", ghost_tug_cooldown)
	return BeehaveNode.SUCCESS

func bt_act_spawn_ghost_bomb(bb: Blackboard) -> int:
	spawn_ghost_bomb()
	set_skill_cooldown(bb, "cd_bomb", ghost_bomb_interval)
	return BeehaveNode.SUCCESS

func bt_act_move_toward_player(_bb: Blackboard) -> int:
	return bt_act_slow_move_to_player(_bb)

func bt_act_dash_attack(bb: Blackboard) -> int:
	anim_play(&"phase3/dash", false)
	set_skill_cooldown(bb, "cd_p3_dash", p3_dash_cooldown)
	return BeehaveNode.SUCCESS

func bt_act_kick(bb: Blackboard) -> int:
	anim_play(&"phase3/kick", false)
	set_skill_cooldown(bb, "cd_p3_kick", p3_kick_cooldown)
	return BeehaveNode.SUCCESS

func bt_act_combo_slash(bb: Blackboard) -> int:
	anim_play(&"phase3/combo1", false)
	set_skill_cooldown(bb, "cd_p3_combo", p3_combo_cooldown)
	return BeehaveNode.SUCCESS

func bt_act_throw_scythe(_bb: Blackboard) -> int:
	anim_play(&"phase3/throw_scythe", false)
	throw_scythe()
	return BeehaveNode.SUCCESS

func bt_act_cast_imprison(bb: Blackboard) -> int:
	anim_play(&"phase3/imprison", false)
	spawn_hell_hand()
	set_skill_cooldown(bb, "cd_p3_imprison", p3_cast_imprison_cooldown)
	return BeehaveNode.SUCCESS

func bt_act_run_slash(_bb: Blackboard) -> int:
	anim_play(&"phase3/run_slash", false)
	_player_imprisoned = false
	return BeehaveNode.SUCCESS

func bt_act_throw_scythe_upward(_bb: Blackboard) -> int:
	anim_play(&"phase3/throw_up", false)
	throw_scythe()
	_player_imprisoned = false
	return BeehaveNode.SUCCESS

func bt_act_summon_ghosts(bb: Blackboard) -> int:
	anim_play(&"phase3/summon", false)
	spawn_summon_ghost()
	set_skill_cooldown(bb, "cd_p3_summon", p3_summon_cooldown)
	return BeehaveNode.SUCCESS

func bt_act_p3_move_toward_player(_bb: Blackboard) -> int:
	return bt_act_slow_move_to_player(_bb)

func bt_act_p3_idle_no_scythe(_bb: Blackboard) -> int:
	anim_play(&"phase3/idle_no_scythe", true)
	if _scythe_recall_requested:
		recall_scythe()
	return BeehaveNode.RUNNING
