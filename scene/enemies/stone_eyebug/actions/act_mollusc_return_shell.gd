extends ActionLeaf
class_name ActMolluscReturnShell

## 软体虫回壳闭环：播 enter_shell 动画 → 通知壳体恢复 → 销毁自身。
##
## ═══════════════════════════════════════════════════════════════════════════
## ⚠️  设计冻结 — BUG FIX 2025-03-07 — 禁止修改以下标注处，原因已记录
## ═══════════════════════════════════════════════════════════════════════════
##
## 【FIX-A: shell_return_committed 单向锁（2025-03-07）】
##   原设计在 _tick_move 路阻/壳消失 FAILURE 时及 interrupt() 时重置 committed，
##   导致 Seq_Attack 打断 → committed=false → Seq_Escape 重新激活。
##   修复：移除所有 committed=false 调用；mollusc.gd 数据层强制单向锁。
##   语义：committed=true 后 Seq_Escape/Seq_IdleHitEscape 永久 FAILURE。
##   Seq_Attack 在 MOVE_TO_SHELL 阶段仍可打断（设计允许），打断后重试回壳。
##
## 【FIX-B: is_entering_shell 入壳无敌锁（2025-03-07）】
##   BUG-1：ENTER_SHELL 阶段 Seq_Attack 仍可抢占（优先级高于 Seq_ReturnShell），
##     打断后 _phase 被 interrupt() 重置 → enter_shell 反复重播，永远无法完成。
##   BUG-2：apply_hit / on_chain_hit 无保护，_do_hurt() 覆盖 enter_shell 动画
##     → _tick_enter 的 anim_is_finished("enter_shell") 永不成立 → 卡死。
##   修复：dist<=16 时 set_entering_shell(true)，直到 queue_free 前（或 interrupt 时清除）：
##     - CondMolluscPlayerInRange 返回 FAILURE → Seq_Attack 无法打断
##     - apply_hit / on_chain_hit 立即返回 false/0 → 全程无敌
##   ENTER_SHELL 和 FLIP_TO_NORMAL 两个阶段均受此保护。
##
## ═══════════════════════════════════════════════════════════════════════════

enum Phase { MOVE_TO_SHELL, ENTER_SHELL, FLIP_TO_NORMAL }

var _phase: int = Phase.MOVE_TO_SHELL

func before_run(actor: Node, _blackboard: Blackboard) -> void:
	var mollusc := actor as Mollusc
	if mollusc == null:
		return
	_phase = Phase.MOVE_TO_SHELL
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
		Phase.FLIP_TO_NORMAL:
			return _tick_flip_to_normal(mollusc)
	return RUNNING


func _tick_move(mollusc: Mollusc) -> int:
	var shell: Node2D = mollusc.find_empty_shell()
	if shell == null or not is_instance_valid(shell):
		# ⚠️ 设计冻结：禁止在此处重置 committed。壳消失时静默 FAILURE，
		# BT 退到 Act_Idle/Seq_Attack；committed 保持 true，逃跑永久禁用。
		return FAILURE

	var dt := mollusc.get_physics_process_delta_time()
	var dx := shell.global_position.x - mollusc.global_position.x
	var dy := shell.global_position.y - mollusc.global_position.y
	var dist := Vector2(dx, dy).length()

	if dist <= 16.0:
		# 到达壳体位置 → 开始进入动画，同时启用入壳无敌锁
		_phase = Phase.ENTER_SHELL
		mollusc.velocity = Vector2.ZERO
		mollusc.set_entering_shell(true)
		mollusc.anim_play(&"enter_shell", false, false)
		return RUNNING

	# ⚠️ 设计冻结：路阻时返回 FAILURE 但禁止重置 committed。
	# BT 退到 Seq_Attack 或 Act_Idle；下一 BT 帧 Seq_ReturnShell 重新尝试。
	# 逃跑分支永久禁用（由 committed 单向锁保证）。
	if mollusc.is_shell_return_path_blocked(shell):
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
		_phase = Phase.FLIP_TO_NORMAL
		mollusc.anim_play(&"flip_to_normal", false, false)
	return RUNNING


func _tick_flip_to_normal(mollusc: Mollusc) -> int:
	if mollusc.anim_is_finished(&"flip_to_normal"):
		# 回壳完成后 committed 被单向锁拦截（false 无法写入），
		# 但 queue_free() 立即销毁实例，此行实际无效（保留以维持代码意图清晰）。
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
		# ⚠️ 设计冻结：禁止在此处重置 committed（BUG FIX 2025-03-07）。
		# 入壳无敌锁清除：interrupt 只发生在 MOVE_TO_SHELL 阶段
		# （ENTER_SHELL/FLIP_TO_NORMAL 期间 is_entering_shell=true，
		#   CondMolluscPlayerInRange 返回 FAILURE，Seq_Attack 无法打断，
		#   故不存在 ENTER_SHELL 被 interrupt 的路径）。
		mollusc.set_entering_shell(false)
		mollusc.velocity = Vector2.ZERO
	_phase = Phase.MOVE_TO_SHELL
	super(actor, blackboard)
