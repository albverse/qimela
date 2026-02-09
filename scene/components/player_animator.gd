extends Node
class_name PlayerAnimator

## Animator 裁决器（唯一播放动画的模块）
## Phase 2A: 支持 Spine + 三种 attack_mode
## Track0 = locomotion（永远跟随 locomotion_state）
## Track1 = action overlay（action_state != None 时播放）
## 播放模式：
##   OVERLAY_UPPER / OVERLAY_CONTEXT: track1 叠加（不影响 track0）
##   FULLBODY_EXCLUSIVE: 清空所有轨道，全身动画替换 track0

const TRACK_LOCO: int = 0
const TRACK_ACTION: int = 1

## 驱动器模式
enum DriverMode { MOCK, SPINE }
@export var driver_mode: DriverMode = DriverMode.MOCK
@export var spine_sprite_path: NodePath = NodePath("../Visual/SpineSprite")

## 攻击模式常量（避免循环依赖）
const MODE_OVERLAY_UPPER: int = 0
const MODE_OVERLAY_CONTEXT: int = 1
const MODE_FULLBODY_EXCLUSIVE: int = 2

# 动画名映射（locomotion_state → anim name）
const LOCO_ANIM: Dictionary = {
	&"Idle": &"idle",
	&"Walk": &"walk",
	&"Run": &"run",
	&"Jump_up": &"jump_up",
	&"Jump_loop": &"jump_loop",
	&"Jump_down": &"jump_down",
}

# loop 表（true=loop）
const LOCO_LOOP: Dictionary = {
	&"idle": true,
	&"walk": true,
	&"run": true,
	&"jump_up": false,
	&"jump_loop": true,
	&"jump_down": false,
}

# 动画名映射（action_state → anim name）
const ACTION_ANIM: Dictionary = {
	&"Chain_R": &"chain_R",
	&"Chain_L": &"chain_L",
	&"ChainCancel_R": &"anim_chain_cancel_R",
	&"ChainCancel_L": &"anim_chain_cancel_L",
	&"Fuse": &"fuse_progress",
	&"Hurt": &"hurt",
	&"Die": &"die",
}

# Track1 anim → ActionFSM event name
const ACTION_END_MAP: Dictionary = {
	&"chain_R": &"anim_end_attack",
	&"chain_L": &"anim_end_attack",
	&"anim_chain_cancel_R": &"anim_end_attack_cancel",
	&"anim_chain_cancel_L": &"anim_end_attack_cancel",
	&"fuse_progress": &"anim_end_fuse",
	&"fuse_hurt": &"anim_end_hurt",
	&"hurt": &"anim_end_hurt",
	# Sword 动画
	&"sword_light_idle": &"anim_end_attack",
	&"sword_light_move": &"anim_end_attack",
	&"sword_light_air": &"anim_end_attack",
	# Knife 动画
	&"knife_light_idle": &"anim_end_attack",
	&"knife_light_move": &"anim_end_attack",
	&"knife_light_air": &"anim_end_attack",
	# die 是终态，不产生 anim_end
}

# Track0 anim → LocomotionFSM event name（仅非 loop）
const LOCO_END_MAP: Dictionary = {
	&"jump_up": &"anim_end_jump_up",
	&"jump_down": &"anim_end_jump_down",
}

var _player: CharacterBody2D = null
var _driver = null  # AnimDriverMock 或 AnimDriverSpine
var _visual: Node2D = null
var _weapon_controller: WeaponController = null

var _cur_loco_anim: StringName = &""
var _cur_action_anim: StringName = &""
var _cur_action_mode: int = -1  # 记录当前 action 的播放模式（用于判断是否需要清理 track0）
var _manual_chain_anim: bool = false  # 标志：chain动画是由ChainSystem手动触发的，tick不要清理


func setup(player: CharacterBody2D) -> void:
	_player = player
	_weapon_controller = player.weapon_controller if player != null else null

	# 根据 driver_mode 创建对应驱动器
	if driver_mode == DriverMode.SPINE:
		_setup_spine_driver()
	else:
		_setup_mock_driver()

	# Visual 引用
	_visual = _player.get_node_or_null(^"Visual") as Node2D


func _setup_mock_driver() -> void:
	"""创建 Mock 驱动器（Phase 0 兼容）"""
	var mock_driver = AnimDriverMock.new()
	mock_driver.name = "AnimDriverMock"
	add_child(mock_driver)
	mock_driver.anim_completed.connect(_on_anim_completed)
	_driver = mock_driver


func _setup_spine_driver() -> void:
	"""创建 Spine 驱动器（Phase 2A）"""
	var spine_sprite: Node = get_node_or_null(spine_sprite_path)
	if spine_sprite == null:
		push_error("[PlayerAnimator] SpineSprite not found at path: %s" % spine_sprite_path)
		push_error("[PlayerAnimator] Falling back to Mock driver")
		_setup_mock_driver()
		return
	
	# 动态加载 AnimDriverSpine
	var spine_driver_script = load("res://scene/components/anim_driver_spine.gd")
	if spine_driver_script == null:
		push_error("[PlayerAnimator] AnimDriverSpine script not found, falling back to Mock")
		_setup_mock_driver()
		return
	
	var spine_driver = spine_driver_script.new()
	spine_driver.name = "AnimDriverSpine"
	add_child(spine_driver)
	spine_driver.setup(spine_sprite)
	spine_driver.anim_completed.connect(_on_anim_completed)
	_driver = spine_driver
	
	if _player != null and _player.has_method("log_msg"):
		_player.log_msg("ANIM", "Spine driver initialized")


## _compute_context: 计算当前上下文（用于武器动画选择）
func _compute_context() -> String:
	if _player == null:
		return "ground_idle"
	
	var on_floor: bool = _player.is_on_floor()
	if not on_floor:
		return "air"
	
	# 地面：根据 movement.move_intent 判断
	if _player.movement != null:
		var intent: int = _player.movement.move_intent
		if intent == 0:  # MoveIntent.NONE
			return "ground_idle"
		else:
			return "ground_move"
	
	return "ground_idle"


func force_stop_action() -> void:
	"""强制停止 track1 动画（用于武器切换等硬切场景）"""
	_cur_action_anim = &""
	if _driver != null:
		_driver.stop(TRACK_ACTION)


func tick(_dt: float) -> void:
	if _player == null or _driver == null:
		return

	# 读取两层状态
	var loco_state: StringName = _player.get_locomotion_state()
	var action_state: StringName = _player.get_action_state()

	# === Track0: locomotion ===
	# CRITICAL: 如果当前 action 是 FULLBODY_EXCLUSIVE，跳过 locomotion 更新
	var skip_loco_update: bool = (_cur_action_mode == MODE_FULLBODY_EXCLUSIVE)
	
	if not skip_loco_update:
		var target_loco: StringName = LOCO_ANIM.get(loco_state, &"idle")
		if target_loco != _cur_loco_anim:
			var loop: bool = LOCO_LOOP.get(target_loco, true)
			_driver.play(TRACK_LOCO, target_loco, loop)
			_cur_loco_anim = target_loco
			_log_play(TRACK_LOCO, target_loco, loop)

	# === Track1: action overlay ===
	if action_state == &"None":
		# CRITICAL: 如果是手动播放的chain动画，不要清理
		if _manual_chain_anim:
			# chain动画独立运行，不受ActionFSM控制
			pass
		elif _cur_action_anim != &"":
			# 清理 action：如果之前是 FULLBODY，需要恢复 locomotion
			if _cur_action_mode == MODE_FULLBODY_EXCLUSIVE:
				# 恢复 locomotion track0
				var target_loco: StringName = LOCO_ANIM.get(loco_state, &"idle")
				var loop: bool = LOCO_LOOP.get(target_loco, true)
				_driver.play(TRACK_LOCO, target_loco, loop)
				_cur_loco_anim = target_loco
				_log_play(TRACK_LOCO, target_loco, loop)
			else:
				# OVERLAY 模式：只停止 track1
				_driver.stop(TRACK_ACTION)
			
			_cur_action_anim = &""
			_cur_action_mode = -1
	else:
		var target_action: StringName = &""
		var action_mode: int = MODE_OVERLAY_UPPER  # 默认模式
		
		# === 委托式选动画：根据 action_state 和武器类型 ===
		# Hurt / Die 使用固定映射（OVERLAY）
		if action_state == &"Fuse":
			target_action = &"fuse_progress"
			action_mode = MODE_FULLBODY_EXCLUSIVE
		elif action_state == &"Hurt":
			if _player.action_fsm != null and _player.action_fsm.has_method("should_use_fuse_hurt_anim") and _player.action_fsm.should_use_fuse_hurt_anim():
				target_action = &"fuse_hurt"
			else:
				target_action = &"hurt"
			action_mode = MODE_OVERLAY_UPPER
		elif action_state == &"Die":
			target_action = &"die"
			action_mode = MODE_OVERLAY_UPPER
		
		# AttackCancel_R / AttackCancel_L：使用固定cancel动画（OVERLAY）
		elif action_state in [&"AttackCancel_R", &"AttackCancel_L"]:
			var side: String = "R" if action_state == &"AttackCancel_R" else "L"
			if _weapon_controller != null:
				var result: Dictionary = _weapon_controller.cancel(side)
				var anim_name: String = result.get("anim_name", "")
				if anim_name != "":
					target_action = StringName(anim_name)
			# Fallback
			if target_action == &"":
				target_action = &"anim_chain_cancel_R" if side == "R" else &"anim_chain_cancel_L"
			action_mode = MODE_OVERLAY_UPPER
		
		# Attack_R / Attack_L：使用 WeaponController 委托
		elif action_state in [&"Attack_R", &"Attack_L"]:
			if _weapon_controller != null and _player.action_fsm != null:
				var context: String = _compute_context()
				var side: String = "R" if action_state == &"Attack_R" else "L"
				var result: Dictionary = _weapon_controller.attack(context, side)
				var anim_name: String = result.get("anim_name", "")
				action_mode = result.get("mode", MODE_OVERLAY_UPPER)
				if anim_name != "":
					target_action = StringName(anim_name)
			
			# Fallback: chain
			if target_action == &"":
				target_action = &"chain_R" if action_state == &"Attack_R" else &"chain_L"
				action_mode = MODE_OVERLAY_UPPER
		
		if target_action != &"" and target_action != _cur_action_anim:
			# 根据 action_mode 决定播放策略
			if action_mode == MODE_FULLBODY_EXCLUSIVE:
				# FULLBODY: 清空所有轨道，只播这个动画
				if driver_mode == DriverMode.SPINE and _driver.has_method("play"):
					# Spine driver: 使用 EXCLUSIVE 模式（PlayMode.EXCLUSIVE = 1）
					_driver.play(TRACK_LOCO, target_action, false, 1)
				else:
					# Mock driver fallback
					_driver.play(TRACK_LOCO, target_action, false)
				_log_play(TRACK_LOCO, target_action, false)
			else:
				# OVERLAY: track1 叠加播放
				_driver.play(TRACK_ACTION, target_action, false)
				_log_play(TRACK_ACTION, target_action, false)
			
			_cur_action_anim = target_action
			_cur_action_mode = action_mode

	# === facing → Visual 翻转 ===
	if _visual != null:
		var facing: int = _player.facing
		var sign_val: float = _player.facing_visual_sign
		_visual.scale.x = float(facing) * sign_val

	# 驱动 Mock（Spine 自动更新，不需要 tick）
	if _driver != null and _driver.has_method("tick"):
		_driver.tick(_dt)


func _on_anim_completed(track: int, anim_name: StringName) -> void:
	_log_end(track, anim_name)

	if track == TRACK_LOCO:
		# FULLBODY_EXCLUSIVE 动作结束（如 fuse_progress）也可能在 track0 完成
		if _cur_action_mode == MODE_FULLBODY_EXCLUSIVE:
			var fullbody_event: StringName = ACTION_END_MAP.get(anim_name, &"")
			if fullbody_event != &"":
				print("[AnimatorDebug] fullbody action completed on track0 anim=%s event=%s" % [String(anim_name), String(fullbody_event)])
				_player.on_action_anim_end(fullbody_event)
				if anim_name != &"die":
					_cur_action_anim = &""
					_cur_action_mode = -1
				return

		# loop 完成已在 Mock 中被过滤（loop=true 永不触发）
		# 此处只收到非 loop 的 jump_up / jump_down
		var event: StringName = LOCO_END_MAP.get(anim_name, &"")
		if event != &"":
			_player.on_loco_anim_end(event)
		_cur_loco_anim = &""

	elif track == TRACK_ACTION:
		# === CRITICAL: 清除手动chain动画标志 ===
		if anim_name in [&"chain_R", &"chain_L", &"anim_chain_cancel_R", &"anim_chain_cancel_L"]:
			_manual_chain_anim = false
		
		var event: StringName = ACTION_END_MAP.get(anim_name, &"")
		if event != &"":
			_player.on_action_anim_end(event)
		
		# === CRITICAL FIX: die 是终态，不清空 _cur_action_anim ===
		# 防止下一帧 tick 因为 "die" != "" 而重新播放
		if anim_name != &"die":
			_cur_action_anim = &""


## === Chain System 桥接方法 ===
## 供 PlayerChainSystem 调用，桥接到 Spine driver 的骨骼坐标

func get_chain_anchor_position(use_right_hand: bool) -> Vector2:
	## 获取手部锚点（优先 Spine 骨骼 → fallback Marker2D → player 坐标）
	if _driver != null and _driver.has_method("get_bone_world_position"):
		# === CRITICAL FIX: 使用正确的骨骼名 chain_anchor_r/l ===
		var bone_name: String = "chain_anchor_r" if use_right_hand else "chain_anchor_l"
		var pos: Variant = _driver.get_bone_world_position(bone_name)
		if pos is Vector2:
			return pos
	# fallback
	if _player != null:
		var hand_path: NodePath = _player.hand_r_path if use_right_hand else _player.hand_l_path
		var hand: Node2D = _player.get_node_or_null(hand_path) as Node2D
		if hand != null:
			return hand.global_position
		return _player.global_position
	return Vector2.ZERO


func play_chain_fire(slot_idx: int) -> void:
	## Chain 发射动画 — 由 ChainSystem 直接调用
	## 动画独立于 ActionFSM，不受其状态控制
	if _driver == null:
		return
	
	# 根据 slot 确定动画名
	var anim_name: StringName = &"chain_R" if slot_idx == 0 else &"chain_L"
	
	# 直接播放在 track1（overlay）
	_driver.play(TRACK_ACTION, anim_name, false)
	_cur_action_anim = anim_name
	_cur_action_mode = MODE_OVERLAY_UPPER
	_manual_chain_anim = true  # 标记为手动播放，防止tick清理
	
	_log_play(TRACK_ACTION, anim_name, false)
	
	if _player != null and _player.has_method("log_msg"):
		_player.log_msg("ANIM", "play_chain_fire slot=%d anim=%s (manual, protected from tick)" % [slot_idx, anim_name])


func play_chain_cancel(right_active: bool, left_active: bool) -> void:
	if _driver == null:
		return

	var anim_name: StringName = &""
	if right_active:
		anim_name = &"anim_chain_cancel_R"
	elif left_active:
		anim_name = &"anim_chain_cancel_L"
	else:
		return

	_manual_chain_anim = true
	_driver.play(TRACK_ACTION, anim_name, false)
	_log_play(TRACK_ACTION, anim_name, false)


# ── 日志 ──
func _log_play(track: int, anim_name: StringName, loop: bool) -> void:
	if _player != null and _player.has_method("log_msg"):
		_player.log_msg("ANIM", "play track=%d name=%s loop=%s" % [track, anim_name, str(loop)])

func _log_end(track: int, anim_name: StringName) -> void:
	if _player != null and _player.has_method("log_msg"):
		_player.log_msg("ANIM", "end track=%d name=%s" % [track, anim_name])
