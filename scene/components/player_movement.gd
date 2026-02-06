extends Node

var _player: Player
var _visual: Node2D
var _was_on_floor: bool = true
var _is_jumping: bool = false
var _fall_loop_started: bool = false
var _last_left_time: float = -1.0
var _last_right_time: float = -1.0
var _is_running: bool = false
const DOUBLE_TAP_WINDOW: float = 0.25

func _ready() -> void:
	_player = _find_player()
	if _player == null:
		push_error("[Movement] Player not found.")
		set_process(false)
		return
	_visual = _player.get_node_or_null(_player.visual_path) as Node2D
	_was_on_floor = _player.is_on_floor()

func tick(dt: float) -> void:
	var left: bool = Input.is_action_pressed(_player.action_left) if _has_action(_player.action_left) else Input.is_key_pressed(KEY_A)
	var right: bool = Input.is_action_pressed(_player.action_right) if _has_action(_player.action_right) else Input.is_key_pressed(KEY_D)
	var left_just: bool = Input.is_action_just_pressed(_player.action_left) if _has_action(_player.action_left) else false
	var right_just: bool = Input.is_action_just_pressed(_player.action_right) if _has_action(_player.action_right) else false
	
	var now := Time.get_ticks_msec() / 1000.0
	
	if left_just:
		if (now - _last_left_time) < DOUBLE_TAP_WINDOW:
			_is_running = true
		_last_left_time = now
	if right_just:
		if (now - _last_right_time) < DOUBLE_TAP_WINDOW:
			_is_running = true
		_last_right_time = now
	
	if not left and not right:
		_is_running = false
	
	if right and not left:
		_player.facing = 1
	elif left and not right:
		_player.facing = -1
	
	if _visual != null:
		_visual.scale.x = float(_player.facing) * _player.facing_visual_sign
	
	if not _player.is_horizontal_input_locked():
		var dir_x := 0.0
		if left:
			dir_x -= 1.0
		if right:
			dir_x += 1.0
		var speed := _player.move_speed
		if _is_running:
			speed *= _player.run_speed_mult
		_player.velocity.x = dir_x * speed
	else:
		_player.velocity.x = 0.0
	
	_player.velocity.y += _player.gravity * dt
	
	if not _player.is_player_locked():
		var jump_pressed: bool = Input.is_action_just_pressed(_player.action_jump) if _has_action(_player.action_jump) else false
		if _player.is_on_floor() and jump_pressed:
			_player.velocity.y = -_player.jump_speed
			_is_jumping = true
			_fall_loop_started = false
			_play_anim_jump_up()
	
	_update_animation()
	_was_on_floor = _player.is_on_floor()

func _update_animation() -> void:
	if _player.animator == null:
		return
	
	var on_floor := _player.is_on_floor()
	var left: bool = Input.is_action_pressed(_player.action_left) if _has_action(_player.action_left) else Input.is_key_pressed(KEY_A)
	var right: bool = Input.is_action_pressed(_player.action_right) if _has_action(_player.action_right) else Input.is_key_pressed(KEY_D)
	var has_move_input: bool = left or right
	
	if on_floor and not _was_on_floor:
		_is_jumping = false
		_fall_loop_started = false
		if has_move_input:
			if _is_running:
				_player.animator.play_run(true)
			else:
				_player.animator.play_walk(true)
		else:
			_player.animator.play_idle(true)
		return
	
	if not on_floor:
		if _player.velocity.y <= 0:
			_is_jumping = false
		if _player.velocity.y > 0 and not _fall_loop_started:
			_player.animator.play_jump_loop()
			_fall_loop_started = true
		return
	
	if has_move_input:
		if _is_running:
			_player.animator.play_run()
		else:
			_player.animator.play_walk()
	else:
		_player.animator.play_idle()

func _play_anim_jump_up() -> void:
	if _player.animator != null:
		_player.animator.play_jump_up()

func _has_action(a: StringName) -> bool:
	return a != StringName("") and InputMap.has_action(a)

func _find_player() -> Player:
	var p: Node = self
	while p != null and not (p is Player):
		p = p.get_parent()
	return p as Player
