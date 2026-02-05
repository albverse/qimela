extends Node
## 玩家移动组件
## 处理行走、奔跑、跳跃的物理和动画

var _player: Player
var _visual: Node2D

# 跳跃状态追踪
var _was_on_floor: bool = true
var _is_jumping: bool = false  # 是否处于跳跃上升阶段
var _fall_loop_started: bool = false

# 双击检测（用于奔跑）
var _last_left_time: float = -1.0
var _last_right_time: float = -1.0
var _is_running: bool = false
const DOUBLE_TAP_WINDOW: float = 0.25  # 双击时间窗口

func _ready() -> void:
	_player = _find_player()
	if _player == null:
		push_error("[Movement] Player not found in parent chain.")
		set_process(false)
		return

	_visual = _player.get_node_or_null(_player.visual_path) as Node2D
	_was_on_floor = _player.is_on_floor()

func tick(dt: float) -> void:
	var left: bool = Input.is_action_pressed(_player.action_left) if _has_action(_player.action_left) else Input.is_key_pressed(KEY_A)
	var right: bool = Input.is_action_pressed(_player.action_right) if _has_action(_player.action_right) else Input.is_key_pressed(KEY_D)
	var left_just: bool = Input.is_action_just_pressed(_player.action_left) if _has_action(_player.action_left) else Input.is_key_pressed(KEY_A)
	var right_just: bool = Input.is_action_just_pressed(_player.action_right) if _has_action(_player.action_right) else Input.is_key_pressed(KEY_D)
	
	var now := Time.get_ticks_msec() / 1000.0
	
	# 双击检测（奔跑）
	if left_just:
		if (now - _last_left_time) < DOUBLE_TAP_WINDOW:
			_is_running = true
		_last_left_time = now
	if right_just:
		if (now - _last_right_time) < DOUBLE_TAP_WINDOW:
			_is_running = true
		_last_right_time = now
	
	# 松开移动键时停止奔跑
	if not left and not right:
		_is_running = false

	# facing（朝向）
	if right and not left:
		_player.facing = 1
	elif left and not right:
		_player.facing = -1

	# 翻转视觉节点（Spine朝右，facing=1不翻转，facing=-1翻转）
	if _visual != null:
		_visual.scale.x = float(_player.facing) * _player.facing_visual_sign

	# x 轴移动
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

	# y 轴：始终受重力
	_player.velocity.y += _player.gravity * dt

	# 跳跃输入
	if not _player.is_player_locked():
		var jump_pressed: bool = Input.is_action_just_pressed(_player.action_jump) if _has_action(_player.action_jump) else Input.is_key_pressed(KEY_W)
		if _player.is_on_floor() and jump_pressed:
			_player.velocity.y = -_player.jump_speed
			_is_jumping = true
			_fall_loop_started = false
			# 播放跳跃起跳动画
			_play_anim_jump_up()
	
	# 动画状态更新
	_update_animation()
	
	# 更新落地状态
	_was_on_floor = _player.is_on_floor()


func _update_animation() -> void:
	"""根据当前状态更新动画"""
	if _player.animator == null:
		return
	
	var on_floor := _player.is_on_floor()
	var moving: bool = abs(_player.velocity.x) > 10.0  # 显式类型，避免推断失败
	
	# 刚落地
	if on_floor and not _was_on_floor:
		_is_jumping = false
		_fall_loop_started = false
		_player.animator.play_jump_down()
		return
	
	# 空中
	if not on_floor:
		# 上升结束后，进入下落循环
		if _player.velocity.y <= 0:
			_is_jumping = false
		# 仅在真正下落时播放 jump_loop
		if _player.velocity.y > 0 and not _fall_loop_started:
			_player.animator.play_jump_loop()
			_fall_loop_started = true
		# 跳跃上升阶段由 play_jump_up 处理
		return
	
	# 地面状态
	if moving:
		if _player.animator.is_one_shot_playing():
			return
		if _is_running:
			_player.animator.play_run()
		else:
			_player.animator.play_walk()
	else:
		# 一次性动画期间不要强制切 idle
		if not _player.animator.is_one_shot_playing():
			_player.animator.play_idle()


func _play_anim_jump_up() -> void:
	"""播放跳跃起跳动画"""
	if _player.animator != null:
		_player.animator.play_jump_up()


func _has_action(a: StringName) -> bool:
	return a != StringName("") and InputMap.has_action(a)


func _find_player() -> Player:
	var p: Node = self
	while p != null and not (p is Player):
		p = p.get_parent()
	return p as Player
