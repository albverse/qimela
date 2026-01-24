extends Node

var _player: Player
var _visual: Node2D

func _ready() -> void:
	_player = _find_player()
	if _player == null:
		push_error("[Movement] Player not found in parent chain.")
		set_process(false)
		return

	_visual = _player.get_node_or_null(_player.visual_path) as Node2D

func tick(dt: float) -> void:
	var left: bool = Input.is_action_pressed(_player.action_left) if _has_action(_player.action_left) else Input.is_key_pressed(KEY_A)
	var right: bool = Input.is_action_pressed(_player.action_right) if _has_action(_player.action_right) else Input.is_key_pressed(KEY_D)

	# facing
	if right and not left:
		_player.facing = 1
	elif left and not right:
		_player.facing = -1

	if _visual != null:
		_visual.scale.x = float(_player.facing) * _player.facing_visual_sign

	# x 轴：锁定则 0，否则按输入
	if not _player.is_horizontal_input_locked():
		var dir_x := 0.0
		if left:
			dir_x -= 1.0
		if right:
			dir_x += 1.0
		_player.velocity.x = dir_x * _player.move_speed
	else:
		_player.velocity.x = 0.0

	# y 轴：始终受重力
	_player.velocity.y += _player.gravity * dt

	# jump：锁定时禁用
	if not _player.is_player_locked():
		var jump_pressed: bool = Input.is_action_just_pressed(_player.action_jump) if _has_action(_player.action_jump) else Input.is_key_pressed(KEY_W)
		if _player.is_on_floor() and jump_pressed:
			_player.velocity.y = -_player.jump_speed

func _has_action(a: StringName) -> bool:
	return a != StringName("") and InputMap.has_action(a)

func _find_player() -> Player:
	var p: Node = self
	while p != null and not (p is Player):
		p = p.get_parent()
	return p as Player
