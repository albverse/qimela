extends ActionLeaf
class_name ActMolluscReturnShell

## 软体虫回壳闭环：
##   1. before_run 锁定目标壳（优先新壳，其次任意空壳）
##   2. MOVE_TO_SHELL：移向目标壳
##   3. ENTER_SHELL：播 enter_shell 动画 → 通知壳体恢复 → 销毁自身
## 目标壳在 before_run 时确定并缓存，避免每帧重查导致目标跳变（如 home_shell 比新壳近时被误选）。

enum Phase { MOVE_TO_SHELL, ENTER_SHELL }

var _phase: int = Phase.MOVE_TO_SHELL
var _target_shell: Node2D = null


func before_run(actor: Node, _blackboard: Blackboard) -> void:
	var mollusc := actor as Mollusc
	if mollusc == null:
		return
	_phase = Phase.MOVE_TO_SHELL
	mollusc.velocity = Vector2.ZERO
	# 优先锁定新壳（非 home_shell），其次任意空壳（含 home_shell，需满足时间门控）
	_target_shell = mollusc.find_new_shell()
	if _target_shell == null:
		_target_shell = mollusc.find_empty_shell()


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
	if _target_shell == null or not is_instance_valid(_target_shell):
		_target_shell = null
		return FAILURE

	var dt := mollusc.get_physics_process_delta_time()
	var dx := _target_shell.global_position.x - mollusc.global_position.x
	var dy := _target_shell.global_position.y - mollusc.global_position.y
	var dist := Vector2(dx, dy).length()

	if dist <= 16.0:
		# 到达壳体位置 → 开始进入动画
		_phase = Phase.ENTER_SHELL
		mollusc.velocity = Vector2.ZERO
		mollusc.anim_play(&"enter_shell", false, false)
		return RUNNING

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
		# 通知目标壳体恢复
		if _target_shell != null and is_instance_valid(_target_shell):
			if _target_shell.has_method("notify_shell_restored"):
				_target_shell.call("notify_shell_restored")
			if _target_shell.is_in_group("stoneeyebug_shell_empty"):
				_target_shell.remove_from_group("stoneeyebug_shell_empty")
		_target_shell = null
		# 软体销毁自身
		mollusc.queue_free()
		return SUCCESS
	return RUNNING


func interrupt(actor: Node, blackboard: Blackboard) -> void:
	var mollusc := actor as Mollusc
	if mollusc != null:
		mollusc.velocity = Vector2.ZERO
	_phase = Phase.MOVE_TO_SHELL
	_target_shell = null
	super(actor, blackboard)
