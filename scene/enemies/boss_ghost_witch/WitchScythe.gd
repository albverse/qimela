extends MonsterBase
class_name WitchScythe

enum ScytheState { FLYING, RETURNING, RETURN_END }

var _state: int = ScytheState.FLYING
var _player: Node2D
var _boss: BossGhostWitch
var _track_interval: float = 1.0
var _track_count_limit: int = 3
var _track_count: int = 0
var _fly_speed: float = 300.0
var _return_speed: float = 500.0
var _target_pos: Vector2
var _track_t: float = 0.0

var _spine: Node = null
var _current_anim: StringName = &""
var _current_anim_loop: bool = false

func _ready() -> void:
	species_id = &"witch_scythe"
	has_hp = false
	super._ready()
	add_to_group("witch_scythe")
	_target_pos = global_position

	_spine = get_node_or_null("SpineSprite")
	if _spine != null and _spine.has_signal("animation_completed"):
		_spine.animation_completed.connect(_on_anim_completed)
	_play_anim(&"fly", true)

func setup(player: Node2D, boss: BossGhostWitch, track_interval: float, track_count: int, fly_speed: float, return_speed: float) -> void:
	_player = player
	_boss = boss
	_track_interval = track_interval
	_track_count_limit = track_count
	_fly_speed = fly_speed
	_return_speed = return_speed
	_target_pos = player.global_position if player != null else global_position
	print("[WITCH_SCYTHE] setup: tracks=%d interval=%.1f fly_speed=%.0f return_speed=%.0f" % [track_count, track_interval, fly_speed, return_speed])

func setup_tracking(player: Node2D, boss: BossGhostWitch, fly_speed: float) -> void:
	setup(player, boss, 0.1, 1, fly_speed, _return_speed)

func _physics_process(dt: float) -> void:
	match _state:
		ScytheState.FLYING: _tick_flying(dt)
		ScytheState.RETURNING: _tick_returning(dt)
		ScytheState.RETURN_END: _tick_return_end()

func _tick_flying(dt: float) -> void:
	_track_t += dt
	if _track_t >= _track_interval and _player != null and is_instance_valid(_player):
		_target_pos = _player.global_position
		_track_t = 0.0
	global_position = global_position.move_toward(_target_pos, _fly_speed * dt)
	if global_position.distance_to(_target_pos) < 8.0:
		_track_count += 1
		if _track_count >= _track_count_limit:
			_state = ScytheState.RETURNING
			_play_anim(&"return", true)
			print("[WITCH_SCYTHE] FLYING → RETURNING")
		elif _player != null and is_instance_valid(_player):
			_target_pos = _player.global_position
	_damage_player()

func _tick_returning(dt: float) -> void:
	if _boss == null or not is_instance_valid(_boss):
		queue_free()
		return
	global_position = global_position.move_toward(_boss.global_position, _return_speed * dt)
	_damage_player()
	if global_position.distance_to(_boss.global_position) < 10.0:
		_state = ScytheState.RETURN_END
		_play_anim(&"return_end", false)
		print("[WITCH_SCYTHE] RETURNING → RETURN_END")

func _tick_return_end() -> void:
	# 等待 return_end 动画播完再通知 Boss 并销毁
	if _is_current_anim_finished():
		if _boss != null and is_instance_valid(_boss):
			_boss._scythe_in_hand = true
		print("[WITCH_SCYTHE] RETURN_END done → queue_free")
		queue_free()

func recall(_pos: Vector2) -> void:
	_state = ScytheState.RETURNING
	_play_anim(&"return", true)

func _damage_player() -> void:
	for p in get_tree().get_nodes_in_group("player"):
		if p is Node2D and global_position.distance_to(p.global_position) < 40.0 and p.has_method("apply_damage"):
			p.call("apply_damage", 1, global_position)
			print("[WITCH_SCYTHE] damaged player at dist=%.1f state=%d" % [global_position.distance_to(p.global_position), _state])


# ═══ 动画 ═══

func _play_anim(anim_name: StringName, loop: bool) -> void:
	if _spine == null:
		return
	if _current_anim == anim_name and loop == _current_anim_loop:
		return
	_current_anim = anim_name
	_current_anim_loop = loop
	var anim_state: Object = null
	if _spine.has_method("get_animation_state"):
		anim_state = _spine.get_animation_state()
	elif _spine.has_method("getAnimationState"):
		anim_state = _spine.getAnimationState()
	if anim_state == null:
		return
	if anim_state.has_method("set_animation"):
		anim_state.set_animation(String(anim_name), loop, 0)
	elif anim_state.has_method("setAnimation"):
		anim_state.setAnimation(String(anim_name), loop, 0)


func _is_current_anim_finished() -> bool:
	if _current_anim_loop:
		return false
	if _spine == null:
		return true
	var anim_state: Object = null
	if _spine.has_method("get_animation_state"):
		anim_state = _spine.get_animation_state()
	elif _spine.has_method("getAnimationState"):
		anim_state = _spine.getAnimationState()
	if anim_state == null:
		return true
	var entry: Object = null
	if anim_state.has_method("get_current"):
		entry = anim_state.get_current(0)
	if entry == null:
		return true
	if entry.has_method("is_complete"):
		return entry.is_complete()
	elif entry.has_method("isComplete"):
		return entry.isComplete()
	return false


func _on_anim_completed(a1 = null, a2 = null, a3 = null) -> void:
	pass  # 状态转换由 _tick_return_end 轮询驱动
