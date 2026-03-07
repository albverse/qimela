extends ActionLeaf
class_name ActSEBShellFlow

## 石眼虫缩壳流程：（可选 hit_shell）→ retreat_in → IN_SHELL（SUCCESS 交还控制权）。
## 同时用于 Seq_InShell 分支的 Act_InShellWait：in_shell_loop → emerge_out → NORMAL。
##
## 在 Seq_ShellFlow（mode=RETREATING）中的阶段路径：
##   HIT_SHELL  → 播 hit_shell（仅雷花触发）→ RETREAT_IN
##   RETREAT_IN → 播 retreat_in；retreat_done 事件 OR 计时 OR anim_finished → mode=IN_SHELL → SUCCESS
##
## 在 Seq_InShell（mode=IN_SHELL）中的阶段路径（Act_InShellWait）：
##   before_run 检测 mode==IN_SHELL → _phase=IN_SHELL
##   IN_SHELL   → 播 in_shell_loop；5s 无攻击 → EMERGE
##   EMERGE     → 播 emerge_out；emerge_done 事件 OR anim_finished → mode=NORMAL → SUCCESS
##
## ═══════════════════════════════════════════════════════════════════════════
## ⚠️  设计冻结 — BUG FIX 2025-03-07 — 禁止修改以下两处逻辑，原因已记录
## ═══════════════════════════════════════════════════════════════════════════
##
## 【BUG-1: _phase 跨周期污染 → 永久 RUNNING】
##   本脚本同时被 Act_ShellFlow（Seq_ShellFlow）和 Act_InShellWait（Seq_InShell）
##   复用，两个实例各有独立 _phase 字段。
##
##   BUG 路径：
##     第1次 before_run → _start_retreat()（_phase 保持初始 RETREAT_IN）→ 正常
##     _tick_retreat 返回 SUCCESS 时将 _phase 设为 IN_SHELL（已记录此次周期末态）
##     第2次 before_run → 调用 _start_retreat() 但未重置 _phase
##       → _phase 仍为 IN_SHELL → tick() 进入 _tick_in_shell（mode=RETREATING，错误）
##       → 5s 后 _phase 变为 EMERGE
##     第3次 before_run → _phase=EMERGE → _tick_emerge 检测 anim_is_finished("emerge_out")
##       → _current_anim 为 "retreat_in"，条件永不成立 → 永久 RUNNING（完全卡死）
##
##   GhostFist 能解卡的原因：interrupt() 已正确将 _phase 重置为 RETREAT_IN，
##   GhostFist 触发 FLIPPED → interrupt() 调用 → _phase 重置 → 临时恢复。
##
##   修复：before_run() else 分支在调用 _start_retreat() 前显式设置
##         _phase = Phase.RETREAT_IN（见下方 before_run 第 else 分支）。
##
## 【BUG-2: emerge_out 被 hit_shell_small 覆盖 → _tick_emerge 永久等待】
##   stone_eyebug.gd 的 _play_hit_shell_small_feedback() 在临界动画检测中
##   原先缺少 anim_is_playing("emerge_out") 保护，链命中可覆盖 emerge_out，
##   导致 _on_anim_completed("emerge_out") 不再能置位 _current_anim_finished。
##   修复：stone_eyebug.gd in_critical_anim 增加 anim_is_playing("emerge_out") 守卫。
##
## ═══════════════════════════════════════════════════════════════════════════

enum Phase { HIT_SHELL, RETREAT_IN, IN_SHELL, EMERGE }

var _phase: int = Phase.RETREAT_IN
var _retreat_start_ms: int = 0


func before_run(actor: Node, _blackboard: Blackboard) -> void:
	var seb := actor as StoneEyeBug
	if seb == null:
		return
	seb.velocity = Vector2.ZERO

	if seb.mode == StoneEyeBug.Mode.IN_SHELL:
		# 已在壳内（软体回壳后 notify_shell_restored 切到 IN_SHELL）
		_phase = Phase.IN_SHELL
		seb.anim_play(&"in_shell_loop", true, true)
		return

	# 开始缩壳
	var thunder: bool = seb.is_thunder_pending
	seb.is_thunder_pending = false
	seb.ev_retreat_done = false
	seb.ev_emerge_done = false

	if thunder:
		_phase = Phase.HIT_SHELL
		seb.anim_play(&"hit_shell", false, true)
	else:
		_phase = Phase.RETREAT_IN
		_start_retreat(seb)


func tick(actor: Node, _blackboard: Blackboard) -> int:
	var seb := actor as StoneEyeBug
	if seb == null:
		return FAILURE

	match _phase:
		Phase.HIT_SHELL:   return _tick_hit_shell(seb)
		Phase.RETREAT_IN:  return _tick_retreat(seb)
		Phase.IN_SHELL:    return _tick_in_shell(seb)
		Phase.EMERGE:      return _tick_emerge(seb)
	return RUNNING


func _tick_hit_shell(seb: StoneEyeBug) -> int:
	if seb.anim_is_finished(&"hit_shell"):
		_phase = Phase.RETREAT_IN
		_start_retreat(seb)
	return RUNNING


func _start_retreat(seb: StoneEyeBug) -> void:
	seb.mode = StoneEyeBug.Mode.RETREATING
	_retreat_start_ms = StoneEyeBug.now_ms()
	seb.ev_retreat_done = false
	# 缩壳后开启攻击窗口（真正执行仍受 CondSEBAttackReady 的 IN_SHELL + 冷却约束）。
	seb.attack_enabled_after_player_retreat = true
	seb.next_attack_end_ms = max(seb.next_attack_end_ms, StoneEyeBug.now_ms() + int(seb.attack_cd * 1000.0))
	seb.anim_play(&"retreat_in", false, false)


func _tick_retreat(seb: StoneEyeBug) -> int:
	var elapsed_ms: int = StoneEyeBug.now_ms() - _retreat_start_ms
	var retreat_ms: int = int(seb.retreat_time * 1000.0)
	# Spine retreat_done 事件优先；Fallback：计时 + 轮询动画结束
	if seb.ev_retreat_done or elapsed_ms >= retreat_ms or seb.anim_is_finished(&"retreat_in"):
		seb.ev_retreat_done = false
		seb.mode = StoneEyeBug.Mode.IN_SHELL
		seb.shell_last_attacked_ms = StoneEyeBug.now_ms()
		_phase = Phase.IN_SHELL
		seb.anim_play(&"in_shell_loop", true, true)
		# 问题3修复：进入IN_SHELL后返回SUCCESS，让Seq_ShellFlow完成，
		# 下一帧Seq_InShell会接管（因为mode现在是IN_SHELL）
		return SUCCESS
	return RUNNING


func _tick_in_shell(seb: StoneEyeBug) -> int:
	var elapsed_ms: int = StoneEyeBug.now_ms() - seb.shell_last_attacked_ms
	var safe_ms: int = int(seb.shell_safe_time * 1000.0)
	if elapsed_ms >= safe_ms:
		_phase = Phase.EMERGE
		seb.ev_emerge_done = false
		seb.anim_play(&"emerge_out", false, true)
	return RUNNING


func _tick_emerge(seb: StoneEyeBug) -> int:
	# Spine emerge_done 事件优先；Fallback：轮询动画结束
	if seb.ev_emerge_done or seb.anim_is_finished(&"emerge_out"):
		seb.ev_emerge_done = false
		seb.mode = StoneEyeBug.Mode.NORMAL
		return SUCCESS
	return RUNNING


func interrupt(actor: Node, blackboard: Blackboard) -> void:
	var seb := actor as StoneEyeBug
	if seb != null:
		seb.velocity = Vector2.ZERO
		seb.is_thunder_pending = false
		seb.ev_retreat_done = false
		seb.ev_emerge_done = false
		seb.force_close_hit_windows()
	_phase = Phase.RETREAT_IN
	super(actor, blackboard)
