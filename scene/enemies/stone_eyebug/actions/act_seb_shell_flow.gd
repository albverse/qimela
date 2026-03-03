extends ActionLeaf
class_name ActSEBShellFlow

## 石眼虫缩壳流程：（可选 hit_shell）→ retreat_in → in_shell_loop → emerge_out → NORMAL。
##
## 阶段：
##   HIT_SHELL   → 播 hit_shell（仅雷花触发时）→ RETREAT_IN
##   RETREAT_IN  → 播 retreat_in（retreat_time 秒）→ IN_SHELL
##   IN_SHELL    → 播 in_shell_loop，等 shell_safe_time 无攻击 → EMERGE
##   EMERGE      → 播 emerge_out → 完成，mode=NORMAL

enum Phase { HIT_SHELL, RETREAT_IN, IN_SHELL, EMERGE }

var _phase: int = Phase.RETREAT_IN
var _retreat_start_ms: int = 0


func before_run(actor: Node, _blackboard: Blackboard) -> void:
	var seb := actor as StoneEyeBug
	if seb == null:
		return
	seb.velocity = Vector2.ZERO

	if seb.mode == StoneEyeBug.Mode.IN_SHELL:
		# 已在壳内（例如软体回壳后恢复）
		_phase = Phase.IN_SHELL
		seb.anim_play(&"in_shell_loop", true, true)
		return

	# 开始缩壳
	_phase = Phase.HIT_SHELL if seb.is_thunder_pending else Phase.RETREAT_IN
	seb.is_thunder_pending = false

	if _phase == Phase.HIT_SHELL:
		seb.anim_play(&"hit_shell", false, true)
	else:
		_start_retreat(seb)


func tick(actor: Node, _blackboard: Blackboard) -> int:
	var seb := actor as StoneEyeBug
	if seb == null:
		return FAILURE

	match _phase:
		Phase.HIT_SHELL:
			return _tick_hit_shell(seb)
		Phase.RETREAT_IN:
			return _tick_retreat(seb)
		Phase.IN_SHELL:
			return _tick_in_shell(seb)
		Phase.EMERGE:
			return _tick_emerge(seb)
	return RUNNING


func _tick_hit_shell(seb: StoneEyeBug) -> int:
	if seb.anim_is_finished(&"hit_shell"):
		_phase = Phase.RETREAT_IN
		_start_retreat(seb)
	return RUNNING


func _start_retreat(seb: StoneEyeBug) -> void:
	seb.mode = StoneEyeBug.Mode.RETREATING
	_retreat_start_ms = StoneEyeBug.now_ms()
	seb.anim_play(&"retreat_in", false, false)


func _tick_retreat(seb: StoneEyeBug) -> int:
	var elapsed_ms := StoneEyeBug.now_ms() - _retreat_start_ms
	var retreat_ms := int(seb.retreat_time * 1000.0)
	if elapsed_ms >= retreat_ms or seb.anim_is_finished(&"retreat_in"):
		seb.mode = StoneEyeBug.Mode.IN_SHELL
		seb.shell_last_attacked_ms = StoneEyeBug.now_ms()
		_phase = Phase.IN_SHELL
		seb.anim_play(&"in_shell_loop", true, true)
	return RUNNING


func _tick_in_shell(seb: StoneEyeBug) -> int:
	var elapsed_ms := StoneEyeBug.now_ms() - seb.shell_last_attacked_ms
	var safe_ms := int(seb.shell_safe_time * 1000.0)
	if elapsed_ms >= safe_ms:
		_phase = Phase.EMERGE
		seb.anim_play(&"emerge_out", false, true)
	return RUNNING


func _tick_emerge(seb: StoneEyeBug) -> int:
	if seb.anim_is_finished(&"emerge_out"):
		seb.mode = StoneEyeBug.Mode.NORMAL
		return SUCCESS
	return RUNNING


func interrupt(actor: Node, blackboard: Blackboard) -> void:
	var seb := actor as StoneEyeBug
	if seb != null:
		seb.velocity = Vector2.ZERO
		seb.is_thunder_pending = false
	_phase = Phase.RETREAT_IN
	super(actor, blackboard)
