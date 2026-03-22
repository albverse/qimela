extends ActionLeaf
class_name ActSoulDevourerFloatMaintainDistance

## =============================================================================
## act_float_maintain_distance — 漂浮隐身态：维持与玩家距离 + Y 轴 100px 上方 + 随机飘荡（P4 兜底）
## =============================================================================
## 强制隐身时维持 forced_invisible_maintain_dist，超时 5s 后显现（着陆序列）。
## 优先远离玩家；到达目标位置后，进入随机飘荡模式（30-50px 范围）。
## =============================================================================

const FLOAT_Y_OFFSET: float = -100.0      # Y 轴相对玩家偏移（负=向上）
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
		var maintain_dist: float = sd.forced_invisible_maintain_dist if sd._forced_invisible else 150.0
		var dist: float = sd.global_position.distance_to(player.global_position)

		if dist < maintain_dist:
			# 优先：远离玩家（仅水平方向远离，Y 轴保持 FLOAT_Y_OFFSET）
			var away_x: float = sd.global_position.x - player.global_position.x
			var target_y: float = player.global_position.y + FLOAT_Y_OFFSET
			var away_dir: Vector2 = Vector2(away_x, sd.global_position.y - target_y).normalized()
			if away_dir == Vector2.ZERO:
				away_dir = Vector2(1.0, -1.0).normalized()
			sd.velocity = away_dir * sd.float_move_speed
			sd.anim_play(&"normal/float_move", true)
			_wander_target = Vector2.ZERO  # 远离时重置飘荡目标
		else:
			# 已与玩家保持安全距离：驶向目标悬浮高度 + 随机飘荡
			var ideal_pos: Vector2 = Vector2(player.global_position.x, player.global_position.y + FLOAT_Y_OFFSET)

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

	sd.move_and_slide()
	return RUNNING


func interrupt(actor: Node, blackboard: Blackboard) -> void:
	var sd: SoulDevourer = actor as SoulDevourer
	if sd != null:
		sd.velocity = Vector2.ZERO
	super(actor, blackboard)
