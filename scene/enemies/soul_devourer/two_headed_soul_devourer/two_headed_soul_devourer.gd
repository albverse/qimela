extends CharacterBody2D
class_name TwoHeadedSoulDevourer

## =============================================================================
## TwoHeadedSoulDevourer — 双头噬魂犬（临时合体实体）
## =============================================================================
## 蓝图：docs/progress/SOUL_DEVOURER_BLUEPRINT.md §2.2 / §15
##
## - 不继承 MonsterBase（无敌，无 HP）
## - 独立场景，不走 FusionRegistry
## - 流程：enter → fall_loop → land → dual_beam → split → 分离还原两只犬
## - 落地后无敌，双向光炮后分离
## =============================================================================

const GRAVITY: float = 1200.0

# 合体来源（持有引用用于分离时还原）
var _source_a: WeakRef = null  # instance_id 较小者（发起方）
var _source_b: WeakRef = null  # instance_id 较大者

var _combined_hp: int = 0
var _merged_aggro: bool = false

# 动画驱动
var _current_anim: StringName = &""
var _current_anim_finished: bool = false
var _anim_driver: AnimDriverSpine = null
var _anim_mock: AnimDriverMock = null

@onready var _spine_sprite: Node = get_node_or_null("SpineSprite")
@onready var _ground_raycast: RayCast2D = get_node_or_null("GroundRaycast") as RayCast2D
@onready var _dual_beam_l: Area2D = get_node_or_null("DualBeamHitboxLeft") as Area2D
@onready var _dual_beam_r: Area2D = get_node_or_null("DualBeamHitboxRight") as Area2D
@onready var _split_mark_l: Marker2D = get_node_or_null("SplitMarkLeft") as Marker2D
@onready var _split_mark_r: Marker2D = get_node_or_null("SplitMarkRight") as Marker2D
@onready var _body_col: CollisionShape2D = get_node_or_null("CollisionShape2D") as CollisionShape2D

enum Phase {
	ENTER,
	FALL_LOOP,
	LAND,
	DUAL_BEAM,
	SPLIT,
	DONE,
}

var _phase: int = Phase.ENTER
var _fall_speed: float = 300.0


func _ready() -> void:
	add_to_group("two_headed_soul_devourer")

	# 初始化动画驱动
	if _is_spine_compatible(_spine_sprite):
		_anim_driver = AnimDriverSpine.new()
		add_child(_anim_driver)
		_anim_driver.setup(_spine_sprite)
		_anim_driver.anim_completed.connect(_on_anim_completed)
		if _spine_sprite.has_signal("animation_event"):
			_spine_sprite.animation_event.connect(_on_spine_animation_event)
	else:
		_anim_mock = AnimDriverMock.new()
		add_child(_anim_mock)
		_anim_mock.anim_completed.connect(_on_anim_completed)

	_set_beam_hitboxes(false)
	anim_play(&"enter", false)
	_phase = Phase.ENTER


func _is_spine_compatible(node: Node) -> bool:
	if node == null:
		return false
	if String(node.get_class()) == "SpineSprite":
		return true
	return node.has_method("get_animation_state")


## 由 act_move_to_partner 调用，初始化合体来源
func init_from_merge(combined_hp: int, a: SoulDevourer, b: SoulDevourer) -> void:
	_combined_hp = combined_hp
	_source_a = weakref(a)
	_source_b = weakref(b)
	_merged_aggro = a._aggro_mode or b._aggro_mode


func _physics_process(dt: float) -> void:
	if _anim_mock:
		_anim_mock.tick(dt)

	match _phase:
		Phase.ENTER:
			if anim_is_finished(&"enter"):
				_phase = Phase.FALL_LOOP
				anim_play(&"fall_loop", true)

		Phase.FALL_LOOP:
			velocity.y += GRAVITY * dt
			move_and_slide()
			var on_ground: bool = is_on_floor()
			if _ground_raycast != null:
				on_ground = _ground_raycast.is_colliding()
			if on_ground:
				velocity.y = 0.0
				_phase = Phase.LAND
				anim_play(&"land", false)

		Phase.LAND:
			if anim_is_finished(&"land"):
				_phase = Phase.DUAL_BEAM
				_set_beam_hitboxes(true)
				anim_play(&"dual_beam", false)

		Phase.DUAL_BEAM:
			if anim_is_finished(&"dual_beam"):
				_set_beam_hitboxes(false)
				_phase = Phase.SPLIT
				anim_play(&"split", false)

		Phase.SPLIT:
			if anim_is_finished(&"split"):
				_phase = Phase.DONE
				_do_split()


func _do_split() -> void:
	# 还原两只犬
	var pos_l: Vector2 = global_position + Vector2(-60.0, 0.0)
	var pos_r: Vector2 = global_position + Vector2(60.0, 0.0)
	if _split_mark_l != null:
		pos_l = _split_mark_l.global_position
	if _split_mark_r != null:
		pos_r = _split_mark_r.global_position

	var hp_each: int = max(1, _combined_hp / 2)

	_restore_soul_devourer(_source_a, pos_l, hp_each, -1.0)
	_restore_soul_devourer(_source_b, pos_r, hp_each, 1.0)

	queue_free()


func _restore_soul_devourer(ref: WeakRef, pos: Vector2, hp: int, separate_dir: float) -> void:
	if ref == null:
		return
	var sd: SoulDevourer = ref.get_ref() as SoulDevourer
	if sd == null or not is_instance_valid(sd):
		return
	sd.global_position = pos
	sd.hp = hp
	sd._aggro_mode = sd._aggro_mode or _merged_aggro
	sd._force_separate = true
	sd._death_rebirth_started = false
	sd._is_floating_invisible = false
	sd._forced_invisible = false
	sd._forced_invisible_anim_playing = false
	sd._merging = false
	sd.exit_merged_hidden_state()
	sd.collision_mask = 1  # World(1)
	# 给分离初速度
	sd.velocity = Vector2(separate_dir * 100.0, -50.0)
	# 重启行为树
	var bt: Node = sd.get_node_or_null("BeehaveTree")
	if bt != null:
		if bt.has_method("interrupt"):
			bt.call("interrupt")
		if bt.has_method("enable"):
			bt.call("enable")
	sd.anim_play(&"normal/idle", true)


# =============================================================================
# 动画接口
# =============================================================================

func anim_play(anim_name: StringName, loop: bool) -> void:
	if _current_anim == anim_name and not _current_anim_finished:
		return
	_current_anim = anim_name
	_current_anim_finished = false
	if _anim_driver:
		_anim_driver.play(0, anim_name, loop, AnimDriverSpine.PlayMode.REPLACE_TRACK)
	elif _anim_mock:
		_anim_mock.play(0, anim_name, loop)


func anim_is_finished(anim_name: StringName) -> bool:
	return _current_anim == anim_name and _current_anim_finished


func _on_anim_completed(_track: int, anim_name: StringName) -> void:
	if anim_name == _current_anim:
		_current_anim_finished = true


func _on_spine_animation_event(a1, a2, a3, a4) -> void:
	var spine_event: Object = null
	for a in [a1, a2, a3, a4]:
		if a is Object and a.has_method("get_data"):
			spine_event = a
			break
	if spine_event == null:
		return
	var data = spine_event.get_data()
	if data == null:
		return
	var event_name: StringName = &""
	if data.has_method("get_event_name"):
		event_name = StringName(data.get_event_name())
	elif data.has_method("getName"):
		event_name = StringName(data.call("getName"))
	match event_name:
		&"atk_hit_on":
			_set_beam_hitboxes(true)
		&"atk_hit_off":
			_set_beam_hitboxes(false)


func _set_beam_hitboxes(enabled: bool) -> void:
	for hitbox in [_dual_beam_l, _dual_beam_r]:
		if hitbox == null:
			continue
		hitbox.monitoring = enabled
		var cs: CollisionShape2D = hitbox.get_node_or_null("CollisionShape2D") as CollisionShape2D
		if cs:
			cs.disabled = not enabled
