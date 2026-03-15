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

func _ready() -> void:
	species_id = &"witch_scythe"
	has_hp = false
	super._ready()
	add_to_group("witch_scythe")
	_target_pos = global_position

func setup(player: Node2D, boss: BossGhostWitch, track_interval: float, track_count: int, fly_speed: float, return_speed: float) -> void:
	_player = player
	_boss = boss
	_track_interval = track_interval
	_track_count_limit = track_count
	_fly_speed = fly_speed
	_return_speed = return_speed
	_target_pos = player.global_position if player != null else global_position

func setup_tracking(player: Node2D, boss: BossGhostWitch, fly_speed: float) -> void:
	setup(player, boss, 0.1, 1, fly_speed, _return_speed)

func _physics_process(dt: float) -> void:
	match _state:
		ScytheState.FLYING: _tick_flying(dt)
		ScytheState.RETURNING: _tick_returning(dt)
		ScytheState.RETURN_END: _tick_return_end()

func _tick_flying(dt: float) -> void:
	_track_t += dt
	if _track_t >= _track_interval and _player != null:
		_target_pos = _player.global_position
		_track_t = 0.0
	global_position = global_position.move_toward(_target_pos, _fly_speed * dt)
	if global_position.distance_to(_target_pos) < 8.0:
		_track_count += 1
		if _track_count >= _track_count_limit:
			_state = ScytheState.RETURNING
		elif _player != null:
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

func _tick_return_end() -> void:
	if _boss != null and is_instance_valid(_boss):
		_boss._scythe_in_hand = true
	queue_free()

func recall(_pos: Vector2) -> void:
	_state = ScytheState.RETURNING

func _damage_player() -> void:
	for p in get_tree().get_nodes_in_group("player"):
		if p is Node2D and global_position.distance_to(p.global_position) < 24.0 and p.has_method("apply_damage"):
			p.call("apply_damage", 1, global_position)
