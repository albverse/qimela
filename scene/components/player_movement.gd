extends Node
class_name PlayerMovement

## Movement 只负责：
##   - 水平速度（根据 move_intent + facing）
##   - 重力
##   - 落地 vy 夹断（不累积）
##   - 消费 jump_request（单一跳跃冲量入口）
## 禁止：直接处理 W 跳跃、任何状态机转移、播放动画

enum MoveIntent { NONE, WALK, RUN }

var _player: CharacterBody2D = null

# 当前意图（每帧由 tick 更新；LocomotionFSM 只读）
var move_intent: int = MoveIntent.NONE

# 原始方向输入（-1/0/+1）
var input_dir: float = 0.0

const INTENT_NAMES: PackedStringArray = ["None", "Walk", "Run"]

func intent_name() -> String:
	return INTENT_NAMES[move_intent] if move_intent >= 0 and move_intent < INTENT_NAMES.size() else "?"

func setup(player: CharacterBody2D) -> void:
	_player = player


func tick(dt: float) -> void:
	if _player == null:
		return
	
	# === CRITICAL FIX: Die状态冻结移动 ===
	if _player.action_fsm != null and _player.action_fsm.state == _player.action_fsm.State.DIE:
		# 强制停止一切移动
		_player.velocity.x = 0.0
		move_intent = MoveIntent.NONE
		input_dir = 0.0
		return  # 不处理任何输入

	# ── 读取输入 ──
	var left: bool = _action_pressed(_player.action_left, KEY_A)
	var right: bool = _action_pressed(_player.action_right, KEY_D)
	var shift: bool = Input.is_key_pressed(KEY_SHIFT)

	input_dir = 0.0
	if right and not left:
		input_dir = 1.0
	elif left and not right:
		input_dir = -1.0

	# ── move_intent ──
	if is_zero_approx(input_dir):
		move_intent = MoveIntent.NONE
	elif shift:
		move_intent = MoveIntent.RUN
	else:
		move_intent = MoveIntent.WALK

	# ── facing（只在有输入时更新）──
	if input_dir > 0.0:
		_player.facing = 1
	elif input_dir < 0.0:
		_player.facing = -1

	# ── 水平速度 ──
	if _player.is_horizontal_input_locked():
		_player.velocity.x = 0.0
	else:
		var speed: float = _player.move_speed
		if move_intent == MoveIntent.RUN:
			speed *= _player.run_speed_mult
		_player.velocity.x = input_dir * speed

	# ── 重力 ──
	_player.velocity.y += _player.gravity * dt

	# ── 消费 jump_request（单一入口：冲量由 LocomotionFSM 请求）──
	if _player.jump_request:
		_player.velocity.y = -_player.jump_speed
		_player.jump_request = false
		if _player.has_method("log_msg"):
			_player.log_msg("MOVE", "jump_request consumed vy=%.1f" % _player.velocity.y)

	# ── 落地 vy 夹断（避免重力累积导致弹跳）──
	if _player.is_on_floor() and _player.velocity.y > 0.0:
		_player.velocity.y = 0.0


func _action_pressed(action: StringName, fallback_key: int) -> bool:
	if action != &"" and InputMap.has_action(action):
		return Input.is_action_pressed(action)
	return Input.is_key_pressed(fallback_key)
