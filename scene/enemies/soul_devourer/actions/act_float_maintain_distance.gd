extends ActionLeaf
class_name ActSoulDevourerFloatMaintainDistance

## =============================================================================
## act_float_maintain_distance — 漂浮隐身态：维持与玩家距离 + 优先飞到玩家上方 200px + 随机飘荡（P4 兜底）
## =============================================================================
## 强制隐身时维持 forced_invisible_maintain_dist，超时 5s 后显现（着陆序列）。
## 优先远离玩家；到达目标位置后，进入随机飘荡模式（30-50px 范围）。
## =============================================================================

const FLOAT_Y_OFFSET: float = -200.0      # Y 轴相对玩家偏移（负=向上）
const MIN_X_DISTANCE: float = 250.0      # X 轴与玩家最小距离（每帧检测）
const WANDER_MIN: float = 30.0            # 随机飘荡最小半径
const WANDER_MAX: float = 50.0            # 随机飘荡最大半径
const ARRIVE_THRESHOLD: float = 20.0      # 到达目标点判定距离

var _timer: float = 0.0
var _wander_target: Vector2 = Vector2.ZERO
var _wander_timer: float = 0.0
const WANDER_INTERVAL: float = 2.5        # 随机飘荡目标重新选择间隔


func before_run(actor: Node, _blackboard: Blackboard) -> void:
	_timer = 0.0
	_wander_timer = 0.0
	_wander_target = Vector2.ZERO
	var sd: SoulDevourer = actor as SoulDevourer
	if sd == null:
		return
	sd.anim_play(&"normal/float_idle", true)


func tick(actor: Node, _blackboard: Blackboard) -> int:
	var sd: SoulDevourer = actor as SoulDevourer
	if sd == null:
		return FAILURE

	var dt: float = get_physics_process_delta_time()
	_timer += dt

	# 强制隐身超时后恢复显现
	if sd._forced_invisible:
		if _timer >= sd.forced_invisible_duration:
			sd._forced_invisible = false
			sd._exit_floating_invisible_to_landing(0.0)
			return SUCCESS
	else:
		# 普通隐身：如果 light_counter 超过阈值，开始着陆
		if sd.light_counter >= sd.light_counter_max:
			sd._exit_floating_invisible_to_landing(0.0)
			return SUCCESS

	var player: Node2D = sd.get_priority_attack_target()

	if player != null:
		var dx_to_player: float = absf(sd.global_position.x - player.global_position.x)
		var ideal_pos: Vector2 = Vector2(player.global_position.x, player.global_position.y + FLOAT_Y_OFFSET)

		# 每帧检测：X 轴距离必须 >= MIN_X_DISTANCE（250px）
		if dx_to_player < MIN_X_DISTANCE:
			# 优先：在 X 轴上远离玩家至 250px，同时飞到玩家上方
			var away_dir_x: float = sign(sd.global_position.x - player.global_position.x)
			if is_zero_approx(away_dir_x):
				away_dir_x = 1.0
			var retreat_target: Vector2 = Vector2(
				player.global_position.x + away_dir_x * MIN_X_DISTANCE,
				ideal_pos.y
			)
			var to_retreat: Vector2 = retreat_target - sd.global_position
			if to_retreat == Vector2.ZERO:
				to_retreat = Vector2(away_dir_x, -1.0)
			sd.velocity = to_retreat.normalized() * sd.float_move_speed * 2.0
			sd.anim_play(&"normal/float_move", true)
			_wander_target = Vector2.ZERO  # 远离时重置飘荡目标
		else:
			# 已与玩家保持安全距离：驶向目标悬浮高度 + 随机飘荡
			# 飘荡目标刷新
			_wander_timer -= dt
			if _wander_target == Vector2.ZERO or _wander_timer <= 0.0:
				var angle: float = randf() * TAU
				var radius: float = randf_range(WANDER_MIN, WANDER_MAX)
				_wander_target = ideal_pos + Vector2(cos(angle), sin(angle)) * radius
				_wander_timer = WANDER_INTERVAL

			var to_wander: Vector2 = _wander_target - sd.global_position
			if to_wander.length() > ARRIVE_THRESHOLD:
				sd.velocity = to_wander.normalized() * sd.float_move_speed
				sd.anim_play(&"normal/float_move", true)
			else:
				sd.velocity = sd.velocity.move_toward(Vector2.ZERO, sd.float_move_speed * dt * 4.0)
				if sd.velocity.length() < 5.0:
					sd.velocity = Vector2.ZERO
					sd.anim_play(&"normal/float_idle", true)
	else:
		# 无玩家：随机飘荡（以当前位置为中心）
		_wander_timer -= dt
		if _wander_target == Vector2.ZERO or _wander_timer <= 0.0:
			var angle: float = randf() * TAU
			var radius: float = randf_range(WANDER_MIN, WANDER_MAX)
			_wander_target = sd.global_position + Vector2(cos(angle), sin(angle)) * radius
			_wander_timer = WANDER_INTERVAL

		var to_wander: Vector2 = _wander_target - sd.global_position
		if to_wander.length() > ARRIVE_THRESHOLD:
			sd.velocity = to_wander.normalized() * sd.float_move_speed
			sd.anim_play(&"normal/float_move", true)
		else:
			sd.velocity = sd.velocity.move_toward(Vector2.ZERO, sd.float_move_speed * dt * 4.0)
			if sd.velocity.length() < 5.0:
				sd.velocity = Vector2.ZERO
				sd.anim_play(&"normal/float_idle", true)

	# move_and_slide 由 _physics_process 统一调用
	return RUNNING


func interrupt(actor: Node, blackboard: Blackboard) -> void:
	var sd: SoulDevourer = actor as SoulDevourer
	if sd != null:
		sd.velocity = Vector2.ZERO
	super(actor, blackboard)
