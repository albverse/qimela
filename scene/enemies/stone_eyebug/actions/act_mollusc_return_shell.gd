extends ActionLeaf
class_name ActMolluscReturnShell

## 软体虫回壳闭环：播 enter_shell 动画 → 通知壳体恢复 → 销毁自身。

enum Phase { MOVE_TO_SHELL, ENTER_SHELL }

var _phase: int = Phase.MOVE_TO_SHELL
var _stuck_time: float = 0.0
var _last_dist_to_shell: float = INF


func before_run(actor: Node, _blackboard: Blackboard) -> void:
	var mollusc := actor as Mollusc
	if mollusc == null:
		return
	_phase = Phase.MOVE_TO_SHELL
	_stuck_time = 0.0
	_last_dist_to_shell = INF
	mollusc.set_shell_return_committed(true)
	mollusc.velocity = Vector2.ZERO


func tick(actor: Node, _blackboard: Blackboard) -> int:
	var mollusc := actor as Mollusc
	if mollusc == null:
		return FAILURE

	match _phase:
		Phase.MOVE_TO_SHELL:
			return _tick_move(mollusc)
		Phase.ENTER_SHELL:
			return _tick_enter(mollusc)
	return RUNNING


func _tick_move(mollusc: Mollusc) -> int:
	var shell: Node2D = mollusc.find_empty_shell()
	if shell == null or not is_instance_valid(shell):
		mollusc.set_shell_return_committed(false)
		return FAILURE

	var dt := mollusc.get_physics_process_delta_time()
	var dx := shell.global_position.x - mollusc.global_position.x
	var dy := shell.global_position.y - mollusc.global_position.y
	var dist := Vector2(dx, dy).length()

	if dist <= 16.0:
		# 到达壳体位置 → 开始进入动画
		_phase = Phase.ENTER_SHELL
		mollusc.velocity = Vector2.ZERO
		mollusc.anim_play(&"enter_shell", false, false)
		return RUNNING

	# 回壳期间若遇到正向墙/断崖（路阻），撤销回壳承诺，允许行为树切回逃跑分支重规划。
	if mollusc.is_shell_return_path_blocked(shell):
		mollusc.set_shell_return_committed(false)
		mollusc.velocity = Vector2.ZERO
		return FAILURE

	# 兜底卡死检测：距离长时间不缩短，视为“路过不去”。
	if dist >= _last_dist_to_shell - 1.0:
		_stuck_time += dt
	else:
		_stuck_time = 0.0
	_last_dist_to_shell = dist
	if _stuck_time >= 0.6:
		mollusc.set_shell_return_committed(false)
		mollusc.velocity = Vector2.ZERO
		return FAILURE

	# 移动向壳
	var dir := Vector2(dx, dy).normalized()
	mollusc.velocity = dir * mollusc.escape_speed
	mollusc.velocity.y += mollusc.gravity * dt
	mollusc.move_and_slide()
	if not mollusc.anim_is_playing(&"run"):
		mollusc.anim_play(&"run", true, true)
	return RUNNING


func _tick_enter(mollusc: Mollusc) -> int:
	if mollusc.anim_is_finished(&"enter_shell"):
		mollusc.set_shell_return_committed(false)
		# 通知壳体恢复
		var shell: Node2D = mollusc.find_empty_shell()
		if shell != null and is_instance_valid(shell) and shell.has_method("notify_shell_restored"):
			shell.call("notify_shell_restored")
			# 恢复 group
			if shell.is_in_group("stoneeyebug_shell_empty"):
				shell.remove_from_group("stoneeyebug_shell_empty")
		# 软体销毁自身
		mollusc.queue_free()
		return SUCCESS
	return RUNNING


func interrupt(actor: Node, blackboard: Blackboard) -> void:
	var mollusc := actor as Mollusc
	if mollusc != null:
		mollusc.set_shell_return_committed(false)
		mollusc.velocity = Vector2.ZERO
	_phase = Phase.MOVE_TO_SHELL
	super(actor, blackboard)
