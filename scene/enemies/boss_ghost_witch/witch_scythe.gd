extends Node2D
class_name WitchScythe

## 镰刀实例：fly 动画循环飞行，每次检测玩家位置并转向飞过去
## 检测次数用完后直线回航，到达后播 return_end，播完通知 Boss
## 全程碰到玩家就伤害

enum ScytheState { FLYING, RETURNING, RETURN_END }

var _state: int = ScytheState.FLYING
var _player: Node2D = null
var _boss: Node2D = null
var _track_interval: float = 1.0
var _track_count_max: int = 3
var _track_count: int = 0
var _fly_speed: float = 300.0
var _return_speed: float = 500.0
var _target_pos: Vector2 = Vector2.ZERO
var _track_timer: float = 0.0
var _hit_player_this_frame: bool = false
var _current_anim: StringName = &""
var _current_anim_finished: bool = false
var _current_anim_loop: bool = false

func setup(player: Node2D, boss: Node2D, track_interval: float,
		track_count: int, fly_speed: float, return_speed: float) -> void:
	_player = player
	_boss = boss
	_track_interval = track_interval
	_track_count_max = track_count
	_fly_speed = fly_speed
	_return_speed = return_speed
	_track_count = 0
	_track_timer = 0.0
	_state = ScytheState.FLYING
	_update_target()

func setup_tracking(player: Node2D, boss: Node2D, fly_speed: float) -> void:
	_player = player
	_boss = boss
	_track_interval = 0.0
	_track_count_max = 1
	_fly_speed = fly_speed
	_return_speed = fly_speed * 1.5
	_track_count = 0
	_state = ScytheState.FLYING
	_update_target()

func _ready() -> void:
	add_to_group("witch_scythe")
	_play_anim(&"fly", true)

	var hit_area: Area2D = get_node_or_null("HitArea")
	if hit_area:
		hit_area.body_entered.connect(_on_body_entered)

	var spine: Node = get_node_or_null("SpineSprite")
	if spine and spine.has_signal("animation_completed"):
		spine.animation_completed.connect(_on_anim_completed_raw)

func _on_anim_completed_raw(_ss: Variant, _te: Variant) -> void:
	_current_anim_finished = true

func _physics_process(dt: float) -> void:
	_hit_player_this_frame = false
	match _state:
		ScytheState.FLYING:
			_tick_flying(dt)
		ScytheState.RETURNING:
			_tick_returning(dt)
		ScytheState.RETURN_END:
			_tick_return_end()

func _tick_flying(dt: float) -> void:
	var dir: Vector2 = (_target_pos - global_position).normalized()
	global_position += dir * _fly_speed * dt
	if global_position.distance_to(_target_pos) < 20.0:
		_track_count += 1
		if _track_count >= _track_count_max:
			_state = ScytheState.RETURNING
		else:
			_track_timer = 0.0
			_update_target()
	_track_timer += dt
	if _track_timer >= _track_interval and _track_count < _track_count_max:
		_track_timer = 0.0
		_update_target()

func _tick_returning(dt: float) -> void:
	if _boss == null or not is_instance_valid(_boss):
		queue_free()
		return
	var boss_pos: Vector2 = _boss.global_position
	var dir: Vector2 = (boss_pos - global_position).normalized()
	global_position += dir * _return_speed * dt
	if global_position.distance_to(boss_pos) < 30.0:
		_play_anim(&"return_end", false)
		_state = ScytheState.RETURN_END

func _tick_return_end() -> void:
	if _current_anim == &"return_end" and _current_anim_finished:
		if _boss and is_instance_valid(_boss):
			_boss._scythe_in_hand = true
			_boss._scythe_instance = null
		queue_free()

func recall(_target_pos_override: Vector2) -> void:
	_state = ScytheState.RETURNING

func _update_target() -> void:
	if _player and is_instance_valid(_player):
		_target_pos = _player.global_position

func _on_body_entered(body: Node2D) -> void:
	if _hit_player_this_frame:
		return
	if body.is_in_group("player") and body.has_method("apply_damage"):
		body.call("apply_damage", 1, global_position)
		_hit_player_this_frame = true

func _play_anim(anim_name: StringName, loop: bool) -> void:
	if _current_anim == anim_name and not _current_anim_finished and _current_anim_loop == loop:
		return
	_current_anim = anim_name
	_current_anim_finished = false
	_current_anim_loop = loop
	var spine: Node = get_node_or_null("SpineSprite")
	if spine == null:
		return
	var anim_state: Variant = null
	if spine.has_method("get_animation_state"):
		anim_state = spine.get_animation_state()
	if anim_state and anim_state.has_method("set_animation"):
		anim_state.set_animation(anim_name, loop, 0)
