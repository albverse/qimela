extends ActionLeaf
class_name ActMolluscReturnShell

## 软体虫回壳闭环：播 enter_shell 动画 → 通知壳体恢复 → 销毁自身。
##
## ═══════════════════════════════════════════════════════════════════════════
## ⚠️  设计冻结 — BUG FIX 2025-03-07 — 禁止修改以下标注处，原因已记录
## ═══════════════════════════════════════════════════════════════════════════
##
## 【BUG: shell_return_committed 多处被重置为 false → Seq_Escape 重新激活】
##
##   原设计：_tick_move 路阻/壳消失 FAILURE 时、以及 interrupt() 时，
##   均调用 set_shell_return_committed(false)，导致：
##     - Seq_Attack 抢占 Seq_ReturnShell → interrupt() → committed=false
##       → 攻击结束后 Seq_Escape 重新激活（玩家靠近即逃，不再回壳）
##     - 路阻 FAILURE → committed=false → Seq_Escape 重新激活
##   违反设计规则：一旦决定回壳，Act_Escape 应永久禁用。
##
##   修复（与 mollusc.gd 的单向锁配合）：
##     - 完全移除 _tick_move 两处 set_shell_return_committed(false) 调用
##     - 完全移除 interrupt() 中的 set_shell_return_committed(false) 调用
##     - mollusc.gd 的 set_shell_return_committed() 在数据层强制单向锁：
##       一旦 true 则拒绝 false 回退（即使调用也无效）
##
##   回壳决策后行为语义（committed=true 永久生效）：
##     - Seq_Escape / Seq_IdleHitEscape：永久 FAILURE（CondMolluscPlayerNear/
##       CondMolluscIdleHitEscape 均检测 committed）
##     - Seq_Attack：仍可正常触发（玩家进入攻击范围时攻击）
##     - Seq_ReturnShell：每 BT 帧尝试；路阻时返回 FAILURE，BT 退到 Act_Idle；
##       路畅时继续推进；被 Seq_Attack 打断后下帧重启 _tick_move 继续尝试
##
## ═══════════════════════════════════════════════════════════════════════════

enum Phase { MOVE_TO_SHELL, ENTER_SHELL }

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
		# 到达壳体位置 → 开始进入动画（无敌且不可被打断）
		_phase = Phase.ENTER_SHELL
		mollusc.begin_shell_enter_lock()
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
	if not mollusc.anim_is_playing(&"enter_shell"):
		mollusc.anim_play(&"enter_shell", false, false)
	if mollusc.anim_is_finished(&"enter_shell"):
		_restore_shell_and_finish(mollusc)
		return SUCCESS
	return RUNNING


func _restore_shell_and_finish(mollusc: Mollusc) -> void:
	# 回壳完成后 committed 被单向锁拦截（false 无法写入），
	# 但 queue_free() 立即销毁实例，此行实际无效（保留以维持代码意图清晰）。
	mollusc.end_shell_enter_lock()
	mollusc.set_shell_return_committed(false)
	# 通知壳体恢复（由 StoneEyeBug 壳体播放自身 flip_to_normal）
	var shell: Node2D = mollusc.find_empty_shell()
	if shell != null and is_instance_valid(shell) and shell.has_method("notify_shell_restored"):
		shell.call("notify_shell_restored")
		# 恢复 group
		if shell.is_in_group("stoneeyebug_shell_empty"):
			shell.remove_from_group("stoneeyebug_shell_empty")
	# 软体销毁自身
	mollusc.queue_free()


func interrupt(actor: Node, blackboard: Blackboard) -> void:
	var mollusc := actor as Mollusc
	if mollusc != null:
		# ⚠️ 设计冻结：禁止在此处重置 committed。
		# 被 Seq_Attack 打断后 committed 保持 true；攻击结束后 Seq_ReturnShell 重启。
		# 原来此处有 set_shell_return_committed(false)，已移除（BUG FIX 2025-03-07）。
		mollusc.end_shell_enter_lock()
		mollusc.velocity = Vector2.ZERO
	_phase = Phase.MOVE_TO_SHELL
	super(actor, blackboard)
