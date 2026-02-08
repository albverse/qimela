extends Node
class_name PlayerAnimFSM

enum State {
	IDLE,
	WALK,
	RUN,
	JUMP_UP,
	JUMP_LOOP,
	JUMP_DOWN,
	CHAIN_R,
	CHAIN_L,
	CHAIN_CANCEL_R,
	CHAIN_CANCEL_L,
	HURT,
	DIE,
}

enum MoveIntent { NONE, WALK, RUN }

# ============================================================
# 动画名映射（Inspector 可覆盖）
# 你已确认 Spine 动画名如下：
#   chain_R / chain_L / anim_chain_cancel_R / anim_chain_cancel_L
# ============================================================
@export var anim_idle: StringName = &"idle"
@export var anim_walk: StringName = &"walk"
@export var anim_run: StringName = &"run"
@export var anim_jump_up: StringName = &"jump_up"
@export var anim_jump_loop: StringName = &"jump_loop"
@export var anim_jump_down: StringName = &"jump_down"
@export var anim_chain_r: StringName = &"chain_R"
@export var anim_chain_l: StringName = &"chain_L"
@export var anim_chain_cancel_r: StringName = &"anim_chain_cancel_R"
@export var anim_chain_cancel_l: StringName = &"anim_chain_cancel_L"
@export var anim_hurt: StringName = &"hurt"
@export var anim_die: StringName = &"die"

@export var jump_down_max_time: float = 0.6
@export var action_anim_max_time: float = 1.0
@export var jump_up_vy_fallback: bool = true

@export var spine_sprite_path: NodePath = NodePath("")
var _spine: Node = null
var _player: Player = null

var current_state: int = State.IDLE
var _prev_on_floor: bool = true
var _anim_finished: bool = false
var _current_anim_name: StringName = &""
var _state_elapsed: float = 0.0

var _looping_states: Dictionary = {}
var move_intent: int = MoveIntent.NONE

@export var debug_print: bool = true

func _ready() -> void:
	_player = _find_player()
	if _player == null:
		push_error("[AnimFSM] Player not found in parent chain.")
		return

	_looping_states = {
		State.IDLE: true,
		State.WALK: true,
		State.RUN: true,
		State.JUMP_LOOP: true,
	}

	if spine_sprite_path != NodePath(""):
		_spine = _player.get_node_or_null(spine_sprite_path)
	if _spine == null:
		_spine = _player.get_node_or_null(^"Visual/SpineSprite")
	if _spine == null:
		_spine = _player.get_node_or_null(^"SpineSprite")
	if _spine == null:
		push_error("[AnimFSM] SpineSprite not found. Set spine_sprite_path.")
		return

	_connect_anim_finished()
	_prev_on_floor = _player.is_on_floor()
	_enter_state(State.IDLE)
	if debug_print:
		print("[AnimFSM] _ready done. spine=%s" % _spine.name)


func _connect_anim_finished() -> void:
	if _spine == null:
		return
	for sig_name in [&"animation_completed", &"animation_finished"]:
		if _spine.has_signal(sig_name):
			if not _spine.is_connected(sig_name, _on_spine_animation_completed):
				_spine.connect(sig_name, _on_spine_animation_completed)
			if debug_print:
				print("[AnimFSM] connected signal: %s" % sig_name)
			return
	push_warning("[AnimFSM] No animation_completed signal found on SpineSprite.")


func tick(dt: float) -> void:
	if _player == null:
		return

	var on_floor: bool = _player.is_on_floor()
	var just_landed: bool = on_floor and not _prev_on_floor
	var vy: float = _player.velocity.y

	_state_elapsed += dt

	# 1) GLOBAL Die
	if current_state != State.DIE and _get_hp() <= 0:
		_do_transition(State.DIE, "global_die", on_floor, vy)
		_prev_on_floor = on_floor
		return
	if current_state == State.DIE:
		_prev_on_floor = on_floor
		return

	# 2.5) INVARIANT: 地面态却不在地面 → 纠正到空中态
	if _is_ground_state(current_state) and not on_floor:
		_do_transition(State.JUMP_UP if vy < 0.0 else State.JUMP_LOOP, "ground_left_floor", on_floor, vy)
		_prev_on_floor = on_floor
		return

	# 3) ANIM_END
	if _anim_finished:
		_anim_finished = false
		if debug_print:
			print("[AnimFSM] >>> ANIM_END in state=%s | floor=%s vy=%.1f intent=%s" % [
				_state_name(current_state), str(on_floor), vy, _intent_name(move_intent)])
		_handle_anim_end(on_floor, vy)
		_prev_on_floor = on_floor
		return

	# 4) TOUCH_FLOOR
	if just_landed:
		if debug_print:
			print("[AnimFSM] >>> TOUCH_FLOOR just_landed=true state=%s vy=%.1f" % [
				_state_name(current_state), vy])
		match current_state:
			State.JUMP_UP, State.JUMP_LOOP:
				_do_transition(State.JUMP_DOWN, "touch_floor", on_floor, vy)
				_prev_on_floor = on_floor
				return

	# 5) PHYSICS FALLBACK
	if jump_up_vy_fallback and current_state == State.JUMP_UP:
		if not on_floor and vy >= 0.0:
			_do_transition(State.JUMP_LOOP, "vy_fallback", on_floor, vy)
			_prev_on_floor = on_floor
			return

	# 6) TIMEOUT
	if current_state == State.JUMP_DOWN and _state_elapsed > jump_down_max_time:
		if on_floor:
			_do_transition(_resolve_ground_state(), "timeout_jdown", on_floor, vy)
		else:
			_do_transition(resolve_post_action_state(), "timeout_jdown_air", on_floor, vy)
		_prev_on_floor = on_floor
		return

	if _is_action_state(current_state) and _state_elapsed > action_anim_max_time:
		_do_transition(resolve_post_action_state(), "action_timeout", on_floor, vy)
		_prev_on_floor = on_floor
		return

	# 7) GREEN
	_eval_green(on_floor, vy)

	_prev_on_floor = on_floor


func _handle_anim_end(on_floor: bool, vy: float) -> void:
	match current_state:
		State.JUMP_UP:
			if on_floor:
				_do_transition(State.JUMP_DOWN, "anim_end_jup_floor", on_floor, vy)
			else:
				_do_transition(State.JUMP_LOOP, "anim_end_jup_air", on_floor, vy)

		State.JUMP_DOWN:
			if on_floor:
				_do_transition(_resolve_ground_state(), "anim_end_jdown", on_floor, vy)
			else:
				_do_transition(resolve_post_action_state(), "anim_end_jdown_air", on_floor, vy)

		State.CHAIN_R, State.CHAIN_L, State.CHAIN_CANCEL_R, State.CHAIN_CANCEL_L, State.HURT:
			_do_transition(resolve_post_action_state(), "anim_end_action", on_floor, vy)
		
		State.DIE:
			# === CRITICAL FIX: DIE 是终态，动画结束后什么都不做 ===
			# 不转换状态，不重播动画，保持在最后一帧
			if debug_print:
				print("[AnimFSM] die anim_end — terminal state, no action")

		_:
			if debug_print:
				print("[AnimFSM] anim_end in looping state %s — ignored" % _state_name(current_state))


func _eval_green(on_floor: bool, vy: float) -> void:
	if not on_floor:
		return

	match current_state:
		State.IDLE:
			if move_intent == MoveIntent.RUN:
				_do_transition(State.RUN, "green", on_floor, vy)
			elif move_intent == MoveIntent.WALK:
				_do_transition(State.WALK, "green", on_floor, vy)

		State.WALK:
			if move_intent == MoveIntent.RUN:
				_do_transition(State.RUN, "green", on_floor, vy)
			elif move_intent == MoveIntent.NONE:
				_do_transition(State.IDLE, "green", on_floor, vy)

		State.RUN:
			if move_intent == MoveIntent.WALK:
				_do_transition(State.WALK, "green", on_floor, vy)
			elif move_intent == MoveIntent.NONE:
				_do_transition(State.IDLE, "green", on_floor, vy)


# ============================================================
# 输入事件（由 player.gd _unhandled_input 转发）
# ============================================================

# ✅ 关键改动：不再限制只能 Idle/Walk/Run 才能跳
# 只要在地面且非 Die/Hurt，按 W 就能起跳并切到 Jump_up（符合你说的：地面发射锁链也可跳）
func on_w_pressed() -> void:
	if current_state == State.DIE or current_state == State.HURT:
		return
	if not _player.is_on_floor():
		if debug_print:
			print("[AnimFSM] on_w_pressed BLOCKED: not on_floor state=%s" % _state_name(current_state))
		return

	_player.velocity.y = -_player.jump_speed
	_do_transition(State.JUMP_UP, "input_W", true, _player.velocity.y)


func on_m_pressed() -> void:
	# 当前工程实际由 chain_system.handle_unhandled_input 驱动 FSM，
	# 这里保留接口但不要求你必须用它。
	if current_state == State.DIE or current_state == State.HURT:
		return
	if _player == null or _player.chain == null:
		return
	var chains_arr: Array = _player.chain.chains
	if chains_arr.size() < 2:
		return
	var slot: int = -1
	if chains_arr[0].state == PlayerChainSystem.ChainState.IDLE:
		slot = 0
	elif chains_arr[1].state == PlayerChainSystem.ChainState.IDLE:
		slot = 1
	if slot < 0:
		if debug_print:
			print("[AnimFSM] on_m_pressed BLOCKED: no idle chain slot")
		return
	if slot == 0:
		_do_transition(State.CHAIN_R, "input_M_slot0", _player.is_on_floor(), _player.velocity.y)
	else:
		_do_transition(State.CHAIN_L, "input_M_slot1", _player.is_on_floor(), _player.velocity.y)


func on_x_pressed() -> void:
	if current_state == State.DIE or current_state == State.HURT:
		return
	if _player == null or _player.chain == null:
		return
	var chains_arr: Array = _player.chain.chains
	if chains_arr.size() < 2:
		return
	var r_active: bool = chains_arr[0].state != PlayerChainSystem.ChainState.IDLE
	var l_active: bool = chains_arr[1].state != PlayerChainSystem.ChainState.IDLE
	if not r_active and not l_active:
		if debug_print:
			print("[AnimFSM] on_x_pressed BLOCKED: no active chains")
		return
	if r_active:
		_do_transition(State.CHAIN_CANCEL_R, "input_X_R", _player.is_on_floor(), _player.velocity.y)
	else:
		_do_transition(State.CHAIN_CANCEL_L, "input_X_L", _player.is_on_floor(), _player.velocity.y)


func on_damaged() -> void:
	if current_state == State.DIE:
		return
	if _get_hp() <= 0:
		_do_transition(State.DIE, "damaged_die", _player.is_on_floor(), _player.velocity.y)
		return
	_do_transition(State.HURT, "damaged", _player.is_on_floor(), _player.velocity.y)


# ============================================================
# chain_system 依赖接口
# ============================================================

func play_chain_fire(slot: int) -> void:
	if current_state == State.DIE:
		return
	if slot == 0:
		_do_transition(State.CHAIN_R, "chain_fire_slot0", _player.is_on_floor(), _player.velocity.y)
	else:
		_do_transition(State.CHAIN_L, "chain_fire_slot1", _player.is_on_floor(), _player.velocity.y)

func play_chain_cancel(right_active: bool, left_active: bool) -> void:
	if current_state == State.DIE:
		return
	if right_active:
		_do_transition(State.CHAIN_CANCEL_R, "chain_cancel_R", _player.is_on_floor(), _player.velocity.y)
	elif left_active:
		_do_transition(State.CHAIN_CANCEL_L, "chain_cancel_L", _player.is_on_floor(), _player.velocity.y)

func get_chain_anchor_position(use_right_hand: bool) -> Vector2:
	if _spine != null and _spine.has_method("get_bone_global_position"):
		var bone_name: StringName = &"hand_r" if use_right_hand else &"hand_l"
		var pos: Variant = _spine.call("get_bone_global_position", bone_name)
		if pos is Vector2:
			return pos
	if _player != null:
		var hand: Node2D = null
		if use_right_hand:
			hand = _player.get_node_or_null(_player.hand_r_path) as Node2D
		else:
			hand = _player.get_node_or_null(_player.hand_l_path) as Node2D
		if hand != null:
			return hand.global_position
	if _player != null:
		return _player.global_position
	return Vector2.ZERO


func resolve_post_action_state() -> int:
	if _get_hp() <= 0:
		return State.DIE
	if not _player.is_on_floor():
		if _player.velocity.y < 0.0:
			return State.JUMP_UP
		return State.JUMP_LOOP
	return _resolve_ground_state()

func _resolve_ground_state() -> int:
	if move_intent == MoveIntent.RUN:
		return State.RUN
	if move_intent == MoveIntent.WALK:
		return State.WALK
	return State.IDLE


func _do_transition(new_state: int, reason: String, on_floor: bool, vy: float) -> void:
	if current_state == new_state:
		return
	if current_state == State.DIE:
		return

	var old: int = current_state
	current_state = new_state
	_anim_finished = false
	_state_elapsed = 0.0

	if debug_print:
		print("[AnimFSM] %s -> %s | reason=%s | floor=%s was_floor=%s vy=%.1f intent=%s hp=%d" % [
			_state_name(old),
			_state_name(new_state),
			reason,
			str(on_floor),
			str(_prev_on_floor),
			vy,
			_intent_name(move_intent),
			_get_hp(),
		])

	_enter_state(new_state)


func _enter_state(s: int) -> void:
	var anim_name: StringName = _get_anim_name(s)
	var is_loop: bool = _looping_states.has(s)
	_play_spine_anim(anim_name, is_loop)


func _play_spine_anim(anim_name: StringName, loop: bool) -> void:
	if _spine == null:
		if debug_print:
			print("[AnimFSM] WARN: _spine is null, cannot play '%s'" % anim_name)
		return
	if anim_name == _current_anim_name and loop:
		return

	var old_anim: StringName = _current_anim_name
	_current_anim_name = anim_name
	_anim_finished = false

	if debug_print:
		print("[AnimFSM] play_anim: '%s' -> '%s' loop=%s" % [old_anim, anim_name, str(loop)])

	if _spine.has_method("get_animation_state"):
		var anim_state: Object = _spine.call("get_animation_state")
		if anim_state != null and anim_state.has_method("set_animation"):
			anim_state.call("set_animation", anim_name, loop, 0)
			if debug_print:
				print("[AnimFSM] played via get_animation_state().set_animation()")
			return

	if _spine.has_method("set_animation"):
		_spine.call("set_animation", anim_name, loop)
		if debug_print:
			print("[AnimFSM] played via set_animation()")
		return

	if _spine is AnimationPlayer:
		var ap: AnimationPlayer = _spine as AnimationPlayer
		if ap.has_animation(anim_name):
			ap.play(anim_name)
			if debug_print:
				print("[AnimFSM] played via AnimationPlayer.play()")
			return

	push_warning("[AnimFSM] FAILED to play '%s' — no matching API on %s" % [anim_name, _spine.get_class()])


func _on_spine_animation_completed(_arg0: Variant = null, _arg1: Variant = null, _arg2: Variant = null) -> void:
	if debug_print:
		print("[AnimFSM] signal: anim_completed | state=%s current_anim='%s'" % [
			_state_name(current_state), _current_anim_name])

	if _looping_states.has(current_state):
		if debug_print:
			print("[AnimFSM] signal: ignored (looping state)")
		return

	var expected_anim: StringName = _get_anim_name(current_state)
	if expected_anim != _current_anim_name:
		if debug_print:
			print("[AnimFSM] signal: ignored (expected='%s' but current='%s')" % [expected_anim, _current_anim_name])
		return

	_anim_finished = true
	if debug_print:
		print("[AnimFSM] signal: _anim_finished=true (state=%s)" % _state_name(current_state))


func _is_action_state(s: int) -> bool:
	return s == State.CHAIN_R or s == State.CHAIN_L \
		or s == State.CHAIN_CANCEL_R or s == State.CHAIN_CANCEL_L \
		or s == State.HURT

func _get_hp() -> int:
	if _player == null or _player.health == null:
		return 1
	return _player.health.hp

func _get_anim_name(s: int) -> StringName:
	match s:
		State.IDLE: return anim_idle
		State.WALK: return anim_walk
		State.RUN: return anim_run
		State.JUMP_UP: return anim_jump_up
		State.JUMP_LOOP: return anim_jump_loop
		State.JUMP_DOWN: return anim_jump_down
		State.CHAIN_R: return anim_chain_r
		State.CHAIN_L: return anim_chain_l
		State.CHAIN_CANCEL_R: return anim_chain_cancel_r
		State.CHAIN_CANCEL_L: return anim_chain_cancel_l
		State.HURT: return anim_hurt
		State.DIE: return anim_die
	return anim_idle

func _state_name(s: int) -> String:
	match s:
		State.IDLE: return "Idle"
		State.WALK: return "Walk"
		State.RUN: return "Run"
		State.JUMP_UP: return "Jump_up"
		State.JUMP_LOOP: return "Jump_loop"
		State.JUMP_DOWN: return "Jump_down"
		State.CHAIN_R: return "Chain_R"
		State.CHAIN_L: return "Chain_L"
		State.CHAIN_CANCEL_R: return "ChainCancel_R"
		State.CHAIN_CANCEL_L: return "ChainCancel_L"
		State.HURT: return "Hurt"
		State.DIE: return "Die"
	return "Unknown"

func _intent_name(i: int) -> String:
	match i:
		MoveIntent.NONE: return "NONE"
		MoveIntent.WALK: return "WALK"
		MoveIntent.RUN: return "RUN"
	return "?"

func _find_player() -> Player:
	var p: Node = self
	while p != null and not (p is Player):
		p = p.get_parent()
	return p as Player

func _is_ground_state(s: int) -> bool:
	return s == State.IDLE or s == State.WALK or s == State.RUN
