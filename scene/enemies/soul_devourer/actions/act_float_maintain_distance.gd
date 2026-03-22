extends ActionLeaf
class_name ActSoulDevourerFloatMaintainDistance

## =============================================================================
## act_float_maintain_distance — 漂浮隐身态：维持与玩家 >= 150px 距离（P4 兜底）
## =============================================================================
## 强制隐身时维持 forced_invisible_maintain_dist，超时 5s 后显现（着陆序列）。
## =============================================================================

var _timer: float = 0.0


func before_run(actor: Node, _blackboard: Blackboard) -> void:
	_timer = 0.0
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

	# 与玩家保持距离
	var player: Node2D = sd.get_priority_attack_target()
	if player != null:
		var dist: float = sd.global_position.distance_to(player.global_position)
		var maintain_dist: float = sd.forced_invisible_maintain_dist if sd._forced_invisible else 150.0
		if dist < maintain_dist:
			# 远离玩家
			var away: Vector2 = (sd.global_position - player.global_position).normalized()
			sd.velocity = away * sd.float_move_speed
			sd.anim_play(&"normal/float_move", true)
		else:
			sd.velocity = sd.velocity.move_toward(Vector2.ZERO, sd.float_move_speed * dt * 4.0)
			if sd.velocity.length() < 5.0:
				sd.velocity = Vector2.ZERO
				sd.anim_play(&"normal/float_idle", true)
	else:
		sd.velocity = sd.velocity.move_toward(Vector2.ZERO, sd.float_move_speed * dt * 4.0)
		if sd.velocity.length() < 5.0:
			sd.velocity = Vector2.ZERO

	sd.move_and_slide()
	return RUNNING


func interrupt(actor: Node, blackboard: Blackboard) -> void:
	var sd: SoulDevourer = actor as SoulDevourer
	if sd != null:
		sd.velocity = Vector2.ZERO
	super(actor, blackboard)
