extends Area2D
class_name WitchScythe

enum ScytheState { FLYING, RETURNING, RETURN_END }

var _player: Node2D
var _boss: BossGhostWitch
var _track_interval: float = 1.0
var _track_count_max: int = 3
var _fly_speed: float = 300.0
var _return_speed: float = 500.0
var _track_count: int = 0
var _track_timer: float = 0.0
var _target_pos: Vector2
var _state: int = ScytheState.FLYING

func _ready() -> void:
	add_to_group("witch_scythe")
	body_entered.connect(_on_body_entered)

func setup(player: Node2D, boss: BossGhostWitch, track_interval: float, track_count: int, fly_speed: float, return_speed: float) -> void:
	_player = player
	_boss = boss
	_track_interval = track_interval
	_track_count_max = track_count
	_fly_speed = fly_speed
	_return_speed = return_speed
	_target_pos = _player.global_position if _player else global_position + Vector2.RIGHT * 80.0

func setup_tracking(player: Node2D, boss: BossGhostWitch, fly_speed: float) -> void:
	setup(player, boss, 0.1, 1, fly_speed, _return_speed)

func _physics_process(dt: float) -> void:
	match _state:
		ScytheState.FLYING:
			_tick_flying(dt)
		ScytheState.RETURNING:
			_tick_returning(dt)
		ScytheState.RETURN_END:
			queue_free()

func _tick_flying(dt: float) -> void:
	_track_timer += dt
	if _track_timer >= _track_interval and _player:
		_target_pos = _player.global_position
		_track_timer = 0.0
	global_position = global_position.move_toward(_target_pos, _fly_speed * dt)
	if global_position.distance_to(_target_pos) <= 6.0:
		_track_count += 1
		if _track_count >= _track_count_max:
			_state = ScytheState.RETURNING
		elif _player:
			_target_pos = _player.global_position

func _tick_returning(dt: float) -> void:
	if _boss == null or not is_instance_valid(_boss):
		queue_free()
		return
	global_position = global_position.move_toward(_boss.global_position, _return_speed * dt)
	if global_position.distance_to(_boss.global_position) <= 10.0:
		if _boss.has_method("on_scythe_returned"):
			_boss.on_scythe_returned()
		_state = ScytheState.RETURN_END

func recall(_pos: Vector2) -> void:
	_state = ScytheState.RETURNING

func _on_body_entered(body: Node) -> void:
	if body and body.is_in_group("player") and body.has_method("apply_damage"):
		body.call("apply_damage", 1, global_position)
