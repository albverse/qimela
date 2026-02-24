extends Node
class_name PlayerLocomotionFSM

## LocomotionFSM（移动层）
## 状态：Idle / Walk / Run / Jump_up / Jump_loop / Jump_down
## 输入：is_on_floor, vy, move_intent, W_pressed, touch_floor, anim_end_jump_*
## 输出：state, jump_request
## 禁止：播放动画、处理 Chain/Hurt、改 velocity

enum State { IDLE, WALK, RUN, JUMP_UP, JUMP_LOOP, JUMP_DOWN, DEAD }

const STATE_NAMES: Array[StringName] = [
	&"Idle", &"Walk", &"Run", &"Jump_up", &"Jump_loop", &"Jump_down", &"Dead"
]

var state: int = State.IDLE
var _player: Player = null
var _prev_on_floor: bool = true

## S3: 卡死保护 - Jump_down 超时
var _jump_timeout: float = 1  # 1秒超时（jump_down 动画应该很短）
var _jump_timer: float = 0.0


func state_name() -> StringName:
	return STATE_NAMES[state] if state >= 0 and state < STATE_NAMES.size() else &"?"


func setup(player: Player) -> void:
	_player = player
	state = State.IDLE
	_prev_on_floor = true


func tick(_dt: float) -> void:
	if _player == null:
		return
	
	# === CRITICAL FIX: Die状态检查 ===
	# 当ActionFSM处于Die状态时，LocomotionFSM完全冻结
	if _player.action_fsm != null and _player.action_fsm.state == _player.action_fsm.State.DIE:
		# 如果尚未进入DEAD状态，立即切换
		if state != State.DEAD:
			var die_on_floor: bool = _player.is_on_floor()
			var die_vy: float = _player.velocity.y
			var die_intent: int = _player.movement.move_intent
			_do_transition(State.DEAD, "action_fsm=Die", 100, die_on_floor, die_vy, die_intent)
		return  # 终态：不处理任何逻辑

	var on_floor: bool = _player.is_on_floor()
	var vy: float = _player.velocity.y
	var intent: int = _player.movement.move_intent  # MoveIntent enum

	# === S3: Jump_down 超时保护 ===
	if state == State.JUMP_DOWN:
		_jump_timer += _dt
		if _jump_timer > _jump_timeout:
			if _player.has_method("log_msg"):
				_player.log_msg("LOCO", "TIMEOUT! Jump_down stuck for %.2fs, forcing Idle" % _jump_timer)
			_jump_timer = 0.0
			_do_transition(State.IDLE, "jump_down_timeout", 99, on_floor, vy, intent)
			return
	else:
		_jump_timer = 0.0

	# === 1) GLOBAL: Die 检查（ActionFSM 管，但 Loco 也冻结）===
	# LocomotionFSM 不处理 Die，由 ActionFSM 管理

	# === 2) touch_floor 检测（刚落地）===
	if on_floor and not _prev_on_floor:
		_on_touch_floor(on_floor, vy, intent)

	# === 3) leave_ground 检测（从地面离开，如走下平台）===
	if not on_floor and _prev_on_floor:
		if state == State.IDLE or state == State.WALK or state == State.RUN:
			_do_transition(State.JUMP_LOOP, "leave_ground", 3, on_floor, vy, intent)
			_prev_on_floor = on_floor
			return

	# === 4) vy_fallback：Jump_up 中 vy>=0 但动画尚未结束 → Jump_loop ===
	if state == State.JUMP_UP and not on_floor and vy >= 0.0:
		_do_transition(State.JUMP_LOOP, "vy_fallback", 3, on_floor, vy, intent)
		_prev_on_floor = on_floor
		return

	# === 5) GREEN: 地面态互切（Idle↔Walk↔Run）===
	if on_floor:
		match state:
			State.IDLE:
				if intent == 2:  # Run
					_do_transition(State.RUN, "intent=Run", 2, on_floor, vy, intent)
				elif intent == 1:  # Walk
					_do_transition(State.WALK, "intent=Walk", 1, on_floor, vy, intent)
			State.WALK:
				if intent == 2:
					_do_transition(State.RUN, "intent=Run", 2, on_floor, vy, intent)
				elif intent == 0:  # None
					_do_transition(State.IDLE, "intent=None", 0, on_floor, vy, intent)
			State.RUN:
				if intent == 1:
					_do_transition(State.WALK, "intent=Walk", 1, on_floor, vy, intent)
				elif intent == 0:
					_do_transition(State.IDLE, "intent=None", 0, on_floor, vy, intent)

	_prev_on_floor = on_floor


# ── 外部事件入口 ──

func on_w_pressed() -> void:
	if _player == null:
		return
	
	# === CRITICAL FIX: Die状态忽略输入 ===
	if _player.action_fsm != null and _player.action_fsm.state == _player.action_fsm.State.DIE:
		return
	
	var on_floor: bool = _player.is_on_floor()
	var vy: float = _player.velocity.y
	var intent: int = _player.movement.move_intent

	_log_event("W_pressed", on_floor, vy, intent)

	# 地面态可起跳（允许落地动画中立刻起跳）
	if on_floor and (state == State.IDLE or state == State.WALK or state == State.RUN or state == State.JUMP_DOWN):
		_do_transition(State.JUMP_UP, "W_pressed", 5, on_floor, vy, intent)
		_player.jump_request = true


func on_anim_end_jump_up() -> void:
	if _player == null:
		return
	var on_floor: bool = _player.is_on_floor()
	var vy: float = _player.velocity.y
	var intent: int = _player.movement.move_intent

	_log_event("anim_end_jump_up", on_floor, vy, intent)

	# BLUE guard_id=10: Jump_up → Jump_loop（guard: not is_on_floor）
	if state == State.JUMP_UP and not on_floor:
		_do_transition(State.JUMP_LOOP, "anim_end_jump_up", 3, on_floor, vy, intent)
	# 如果已落地，touch_floor 应已处理


func on_anim_end_jump_down() -> void:
	if _player == null:
		return
	var on_floor: bool = _player.is_on_floor()
	var vy: float = _player.velocity.y
	var intent: int = _player.movement.move_intent

	_log_event("anim_end_jump_down", on_floor, vy, intent)

	# BLUE guard_id=9: Jump_down → Idle/Walk/Run
	if state != State.JUMP_DOWN:
		return
	if not on_floor:
		return

	if intent == 2:
		_do_transition(State.RUN, "jd_end+Run", 3, on_floor, vy, intent)
	elif intent == 1:
		_do_transition(State.WALK, "jd_end+Walk", 2, on_floor, vy, intent)
	else:
		_do_transition(State.IDLE, "jd_end+Idle", 1, on_floor, vy, intent)


# ── 内部事件 ──

func _on_touch_floor(on_floor: bool, vy: float, intent: int) -> void:
	_log_event("touch_floor", on_floor, vy, intent)

	# BLUE guard_id=14: Jump_up → Jump_down
	if state == State.JUMP_UP:
		_do_transition(State.JUMP_DOWN, "touch_floor", 4, on_floor, vy, intent)
		return

	# BLUE guard_id=1: Jump_loop → Jump_down
	if state == State.JUMP_LOOP:
		_do_transition(State.JUMP_DOWN, "touch_floor", 4, on_floor, vy, intent)
		return


# ── 转移执行 ──

func _do_transition(to: int, reason: String, priority: int, on_floor: bool, vy: float, intent: int) -> void:
	var from_name: StringName = state_name()
	state = to
	var to_name: StringName = state_name()

	if from_name == to_name:
		return  # 无实际转移
	
	# === S3: 进入 Jump_down 重置计时器 ===
	if to == State.JUMP_DOWN:
		_jump_timer = 0.0

	if _player != null and _player.has_method("log_msg"):
		_player.log_msg("LOCO",
			"TRANS=%s->%s reason=%s pr=%d floor=%s vy=%.1f intent=%s" % [
				from_name, to_name, reason, priority,
				str(on_floor), vy,
				_player.movement.intent_name() if _player.movement != null else str(intent)
			])


# ── 日志辅助 ──

func _log_event(event: String, on_floor: bool, vy: float, intent: int) -> void:
	if _player != null and _player.has_method("log_msg"):
		_player.log_msg("LOCO",
			"EVENT=%s floor=%s vy=%.1f intent=%s" % [
				event, str(on_floor), vy,
				_player.movement.intent_name() if _player.movement != null else str(intent)
			])
