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
	&"Idle": &"chain_/idle",
	&"Walk": &"chain_/walk",
	&"Run": &"chain_/run",
	&"Jump_up": &"chain_/jump_up",
	&"Jump_loop": &"chain_/jump_loop",
	&"Jump_down": &"chain_/jump_down",
}

# loop 表（true=loop）
const LOCO_LOOP: Dictionary = {
	&"chain_/idle": true,
	&"chain_/walk": true,
	&"chain_/run": true,
	&"chain_/jump_up": false,
	&"chain_/jump_loop": true,
	&"chain_/jump_down": false,
}

# 动画名映射（action_state → anim name）
const ACTION_ANIM: Dictionary = {
	&"Chain_R": &"chain_/chain_R",
	&"Chain_L": &"chain_/chain_L",
	&"ChainCancel_R": &"chain_/anim_chain_cancel_R",
	&"ChainCancel_L": &"chain_/anim_chain_cancel_L",
	&"Fuse": &"chain_/fuse_progress",
	&"Hurt": &"chain_/hurt",
	&"Die": &"chain_/die",
}

# Track1 anim → ActionFSM event name
const ACTION_END_MAP: Dictionary = {
	&"chain_/chain_R": &"anim_end_attack",
	&"chain_/chain_L": &"anim_end_attack",
	&"chain_/anim_chain_cancel_R": &"anim_end_attack_cancel",
	&"chain_/anim_chain_cancel_L": &"anim_end_attack_cancel",
	&"chain_/fuse_progress": &"anim_end_fuse",
	&"chain_/fuse_hurt": &"anim_end_hurt",
	&"chain_/hurt": &"anim_end_hurt",
	&"ghost_fist_/attack_1": &"anim_end_attack",
	&"ghost_fist_/attack_2": &"anim_end_attack",
	&"ghost_fist_/attack_3": &"anim_end_attack",
	&"ghost_fist_/attack_4": &"anim_end_attack",
	&"ghost_fist_/cooldown": &"anim_end_attack",
	&"ghost_fist_/enter": &"anim_end_attack",
	&"ghost_fist_/exit": &"anim_end_attack",
	&"ghost_fist_/hurt": &"anim_end_hurt",
	&"ghost_fist_/die": &"anim_end_hurt",
	# Sword 动画
	&"chain_/sword_light_idle": &"anim_end_attack",
	&"chain_/sword_light_move": &"anim_end_attack",
	&"chain_/sword_light_air": &"anim_end_attack",
	# Knife 动画
	&"chain_/knife_light_idle": &"anim_end_attack",
	&"chain_/knife_light_move": &"anim_end_attack",
	&"chain_/knife_light_air": &"anim_end_attack",
	# die 是终态，不产生 anim_end
}

# Track0 anim → LocomotionFSM event name（仅非 loop）
const LOCO_END_MAP: Dictionary = {
	&"chain_/jump_up": &"anim_end_jump_up",
	&"chain_/jump_down": &"anim_end_jump_down",
	&"ghost_fist_/jump_up": &"anim_end_jump_up",
	&"ghost_fist_/jump_down": &"anim_end_jump_down",
}

# 手动 Chain 动画：不向 ActionFSM 派发结束事件（避免 state=None 噪音和边缘联动）
const MANUAL_CHAIN_ANIMS: Array[StringName] = [
	&"chain_/chain_R", &"chain_/chain_L", &"chain_/anim_chain_cancel_R", &"chain_/anim_chain_cancel_L"
]

var _player: Player = null
var _driver = null  # AnimDriverMock 或 AnimDriverSpine
var _visual: Node2D = null
var _weapon_controller: WeaponController = null

var _cur_loco_anim: StringName = &""
var _cur_action_anim: StringName = &""
var _cur_action_mode: int = -1  # 记录当前 action 的播放模式（用于判断是否需要清理 track0）
var _manual_chain_anim: bool = false  # 标志：chain动画是由ChainSystem手动触发的，tick不要清理

# ── Ghost Fist 引用 ──
var _ghost_fist: GhostFist = null
var _gf_L: SpineSprite = null
var _gf_R: SpineSprite = null
var _gf_mode: bool = false  # 当前是否处于 Ghost Fist 模式


func setup(player: Player) -> void:
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


# ════════════════════════════════════════
# Ghost Fist 初始化
# ════════════════════════════════════════
func setup_ghost_fist(gf: GhostFist) -> void:
	_ghost_fist = gf
	if gf == null:
		_gf_L = null
		_gf_R = null
		return
	_gf_L = gf.get_spine_L()
	_gf_R = gf.get_spine_R()
	_connect_gf_signals()
	if _player != null and _player.has_method("log_msg"):
		_player.log_msg("ANIM", "Ghost Fist setup complete (L=%s R=%s)" % [str(_gf_L != null), str(_gf_R != null)])


func _connect_gf_signals() -> void:
	for node: SpineSprite in [_gf_L, _gf_R]:
		if node == null:
			continue
		var target_node: SpineSprite = node
		if node.has_signal("animation_event"):
			node.animation_event.connect(
				func(a1, a2, a3, a4) -> void:
					var spine_event = null
					for a in [a1, a2, a3, a4]:
						if a is Object and a.has_method("get_data"):
							spine_event = a
							break
					if spine_event != null:
						_on_gf_spine_event(target_node, spine_event)
			)
		if node.has_signal("animation_completed"):
			node.animation_completed.connect(
				func(a1, a2 = null, a3 = null, a4 = null) -> void:
					var track_entry = null
					for a in [a1, a2, a3, a4]:
						if a is Object and a != null and a.has_method("get_track_index"):
							track_entry = a
							break
					_on_gf_anim_complete(target_node, track_entry if track_entry else a1)
			)
	print("[PA_TEST] _connect_gf_signals complete, L=%s R=%s" % [_gf_L != null, _gf_R != null])



## 从可变信号参数中找到 SpineTrackEntry（has get_track_index）
func _find_track_entry(a1, a2, a3, a4):
	for a in [a1, a2, a3, a4]:
		if a is Object and a.has_method("get_track_index"):
			return a
	return a1  # fallback: 第一个参数


## 从可变信号参数中找到 SpineEvent（has get_data）
func _find_spine_event(a1, a2, a3, a4):
	for a in [a1, a2, a3, a4]:
		if a is Object and a.has_method("get_data"):
			return a
	return null


func _on_gf_spine_event(ss: SpineSprite, event: SpineEvent) -> void:
	print("[PA_TEST] _on_gf_spine_event CALLED! ss=%s event=%s" % [ss.name if ss else "null", event != null])
	
	if _ghost_fist == null:
		return
	
	var hand: int = GhostFist.Hand.LEFT if ss == _gf_L else GhostFist.Hand.RIGHT
	var event_name: StringName = &""
	
	# ✅ 修复：使用 get_event_name() 而不是 get_name()
	if event != null and event.has_method("get_data"):
		var data = event.get_data()
		if data != null and data.has_method("get_event_name"):
			event_name = StringName(data.get_event_name())
	
	if event_name == &"":
		return
	
	_ghost_fist.on_spine_event(hand, event_name)


func _on_gf_anim_complete(ss: SpineSprite, entry) -> void:
	if _ghost_fist == null:
		return
	var prev_state: int = _ghost_fist.state
	var gf_state: int = _ghost_fist.state
	var hand: int = GhostFist.Hand.LEFT if ss == _gf_L else GhostFist.Hand.RIGHT

	if gf_state >= GhostFist.GFState.GF_ATTACK_1 and gf_state <= GhostFist.GFState.GF_ATTACK_4:
		var expected: int = GhostFist.ATTACK_HAND.get(gf_state, GhostFist.Hand.RIGHT)
		if hand == expected:
			var anim_name: StringName = _extract_anim_name(entry)
			var expected_stage: int = gf_state - GhostFist.GFState.GF_ATTACK_1 + 1
			var expected_anim: StringName = StringName("ghost_fist_/attack_%d" % expected_stage)
			if anim_name == &"" or anim_name == expected_anim:
				_ghost_fist.on_animation_complete(anim_name)
			else:
				print("[PA] Stale attack completion ignored: got=%s expected=%s" % [anim_name, expected_anim])
		return

	# 非攻击状态（enter/cooldown/exit）只接受 R 手完成，避免 L+R 双触发
	if hand == GhostFist.Hand.RIGHT:
		_ghost_fist.on_animation_complete(_extract_anim_name(entry))
		if prev_state == GhostFist.GFState.GF_COOLDOWN and _ghost_fist.state == GhostFist.GFState.GF_IDLE:
			_cur_loco_anim = &""


func _extract_anim_name(entry) -> StringName:
	if entry != null:
		var anim = null
		if entry.has_method("get_animation"):
			anim = entry.get_animation()
		if anim != null and anim.has_method("get_name"):
			return StringName(anim.get_name())
	return &""


# ════════════════════════════════════════
# Ghost Fist 三节点播放接口
# ════════════════════════════════════════


func _prepare_gf_fullbody_playback() -> void:
	if _player != null:
		_player.velocity.x = 0.0
	# 只清理 overlay 轨（track1），不要 clear track0。
	# clear track0 会把 Spine 停在上一姿势最后一帧（run/hurt 旋转残留），
	# 正确做法是直接用后续 EXCLUSIVE 播放替换 track0。
	if _driver != null and _driver.has_method("stop"):
		_driver.stop(TRACK_ACTION)


## 攻击段播放（三节点同步: PlayerSpine + L + R）
func play_ghost_fist_attack(stage: int) -> void:
	_prepare_gf_fullbody_playback()
	var player_anim: StringName = StringName("ghost_fist_/attack_%d" % stage)
	var weapon_anim: StringName = StringName("ghost_fist_/attack_%d" % stage)
	_play_on_player_spine(player_anim, false)
	_play_on_gf_spine(GhostFist.Hand.LEFT, weapon_anim, false)
	_play_on_gf_spine(GhostFist.Hand.RIGHT, weapon_anim, false)
	_log_play(0, player_anim, false)


## Cooldown 播放（三节点同步）
func play_ghost_fist_cooldown() -> void:
	_prepare_gf_fullbody_playback()
	_play_on_player_spine(&"ghost_fist_/cooldown", false)
	_play_on_gf_spine(GhostFist.Hand.LEFT, &"ghost_fist_/cooldown", false)
	_play_on_gf_spine(GhostFist.Hand.RIGHT, &"ghost_fist_/cooldown", false)
	_log_play(0, &"ghost_fist_/cooldown", false)


## Enter 播放（三节点同步）
func play_ghost_fist_enter() -> void:
	_prepare_gf_fullbody_playback()
	_play_on_player_spine(&"ghost_fist_/enter", false)
	_play_on_gf_spine(GhostFist.Hand.LEFT, &"ghost_fist_/enter", false)
	_play_on_gf_spine(GhostFist.Hand.RIGHT, &"ghost_fist_/enter", false)
	_log_play(0, &"ghost_fist_/enter", false)


## Exit 播放（三节点同步）
func play_ghost_fist_exit() -> void:
	_prepare_gf_fullbody_playback()
	_play_on_player_spine(&"ghost_fist_/exit", false)
	_play_on_gf_spine(GhostFist.Hand.LEFT, &"ghost_fist_/exit", false)
	_play_on_gf_spine(GhostFist.Hand.RIGHT, &"ghost_fist_/exit", false)
	_log_play(0, &"ghost_fist_/exit", false)


func play_ghost_fist_idle_anima() -> void:
	_prepare_gf_fullbody_playback()
	_play_on_player_spine(&"ghost_fist_/idle_anima", false)
	_play_on_gf_spine(GhostFist.Hand.LEFT, &"ghost_fist_/idle_anima", false)
	_play_on_gf_spine(GhostFist.Hand.RIGHT, &"ghost_fist_/idle_anima", false)
	_log_play(0, &"ghost_fist_/idle_anima", false)


## GF 模式下的 locomotion 切换（PlayerSpine 切 GF locomotion + 武器端 idle）
func switch_ghost_fist_locomotion(key: StringName) -> void:
	var profile: Dictionary = WeaponAnimProfiles.get_profile("GHOST_FIST")
	var loco_map: Dictionary = profile.get("locomotion", {})
	var player_anim: StringName = loco_map.get(String(key), &"ghost_fist_/idle")
	var loop: bool = key in [&"idle", &"walk", &"run", &"jump_loop"]
	_play_on_player_spine(player_anim, loop)
	# 武器端在 locomotion 时播放 idle（悬浮跟随）
	_play_on_gf_spine(GhostFist.Hand.LEFT, &"ghost_fist_/idle", true)
	_play_on_gf_spine(GhostFist.Hand.RIGHT, &"ghost_fist_/idle", true)


## 内部: 在 PlayerSpine 上播放
func _play_on_player_spine(anim_name: StringName, loop: bool) -> void:
	if _driver == null:
		return
	if driver_mode == DriverMode.SPINE:
		_driver.play(TRACK_LOCO, anim_name, loop, AnimDriverSpine.PlayMode.EXCLUSIVE)
	else:
		_driver.play(TRACK_LOCO, anim_name, loop)
	_cur_loco_anim = anim_name
	_cur_action_anim = anim_name  # GF 模式下标记为活跃
	_cur_action_mode = MODE_FULLBODY_EXCLUSIVE


## 内部: 在 GF SpineSprite 上播放
func _play_on_gf_spine(hand: int, anim_name: StringName, loop: bool) -> void:
	var spine: SpineSprite = _gf_L if hand == GhostFist.Hand.LEFT else _gf_R
	if spine == null:
		return
	var anim_state = spine.get_animation_state()
	if anim_state == null:
		return
	anim_state.set_animation(String(anim_name), loop, 0)


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
	_cur_action_mode = -1
	if _driver != null:
		_driver.stop(TRACK_ACTION)


func set_gf_mode(enabled: bool) -> void:
	_gf_mode = enabled
	if enabled:
		# 进入 GF 模式：重置 loco 使下帧强制更新
		_cur_loco_anim = &""
	else:
		# 退出 GF 模式：重置 loco 使下帧恢复默认动画
		_cur_loco_anim = &""
		_cur_action_anim = &""
		_cur_action_mode = -1


func tick(_dt: float) -> void:
	if _player == null or _driver == null:
		return

	# 读取两层状态
	var loco_state: StringName = _player.get_locomotion_state()
	var action_state: StringName = _player.get_action_state()

	# Die 优先级最高：立即阻断手动 chain，并清理 track1
	if action_state == &"Die":
		_manual_chain_anim = false
		if _cur_action_anim != &"" and _cur_action_anim != &"chain_/die" and _cur_action_anim != &"ghost_fist_/die" and _driver.has_method("stop"):
			_driver.stop(TRACK_ACTION)

	# === Ghost Fist 模式: 独立 locomotion 驱动 ===
	if _gf_mode and _ghost_fist != null and _ghost_fist.is_active():
		var gf_fullbody_playing: bool = _cur_action_mode == MODE_FULLBODY_EXCLUSIVE and _cur_action_anim.begins_with("ghost_fist_/")
		# GF 模式下，只在 IDLE 状态时更新 locomotion（攻击/cooldown/enter/exit 由专用方法播放）
		if _ghost_fist.state == GhostFist.GFState.GF_IDLE:
			# FULLBODY_EXCLUSIVE（enter/cooldown/exit/idle_anima）播放期间不要覆盖
			if not gf_fullbody_playing:
				# GF 模式使用基础 locomotion 键（不带 chain_/ 前缀）
				var base_loco_key: StringName = GF_BASE_LOCO.get(loco_state, &"idle")
				var gf_loco_anim: StringName = _get_gf_loco_anim(base_loco_key)
				if gf_loco_anim != _cur_loco_anim:
					var loop: bool = base_loco_key in [&"idle", &"walk", &"run", &"jump_loop"]
					# GF locomotion: 直接播放在 TRACK_LOCO，不用 EXCLUSIVE 模式
					# 不设 action 字段 — jump_up/jump_down 完成时走 LOCO_END_MAP 而非 FULLBODY 路径
					_driver.play(TRACK_LOCO, gf_loco_anim, loop)
					_play_on_gf_spine(GhostFist.Hand.LEFT, &"ghost_fist_/idle", true)
					_play_on_gf_spine(GhostFist.Hand.RIGHT, &"ghost_fist_/idle", true)
					_cur_loco_anim = gf_loco_anim
					_cur_action_anim = &""
					_cur_action_mode = -1
					_log_play(TRACK_LOCO, gf_loco_anim, loop)
		# GF 模式: Hurt/Die 需特殊处理
		if action_state == &"Hurt":
			var hurt_anim: StringName = &"ghost_fist_/hurt"
			if hurt_anim != _cur_action_anim:
				if _ghost_fist.has_method("on_hurt"):
					_ghost_fist.on_hurt()
				elif _ghost_fist.state != GhostFist.GFState.GF_IDLE and _ghost_fist.state != GhostFist.GFState.GF_ENTER:
					_ghost_fist.state = GhostFist.GFState.GF_IDLE
					_ghost_fist.queued_next = false
					_ghost_fist.hit_confirmed = false
					_ghost_fist._disable_all_hitboxes()
				_play_on_player_spine(hurt_anim, false)
				_play_on_gf_spine(GhostFist.Hand.LEFT, hurt_anim, false)
				_play_on_gf_spine(GhostFist.Hand.RIGHT, hurt_anim, false)
				_cur_action_anim = hurt_anim
		elif action_state == &"Die":
			var die_anim: StringName = &"ghost_fist_/die"
			if die_anim != _cur_action_anim:
				if _ghost_fist.has_method("on_die"):
					_ghost_fist.on_die()
				elif _ghost_fist.state != GhostFist.GFState.GF_IDLE:
					_ghost_fist.state = GhostFist.GFState.GF_IDLE
					_ghost_fist.queued_next = false
					_ghost_fist.hit_confirmed = false
					_ghost_fist._disable_all_hitboxes()
				_play_on_player_spine(die_anim, false)
				_play_on_gf_spine(GhostFist.Hand.LEFT, die_anim, false)
				_play_on_gf_spine(GhostFist.Hand.RIGHT, die_anim, false)
				_cur_action_anim = die_anim
				_gf_mode = false
		# facing
		if _visual != null:
			var facing_val: int = _player.facing
			var sign_val: float = _player.facing_visual_sign
			_visual.scale.x = float(facing_val) * sign_val
		# GF hitbox 跟随
		_ghost_fist.update_hitbox_positions()
		if _driver != null and _driver.has_method("tick"):
			_driver.tick(_dt)
		return  # GF 模式不走标准 tick 流程

	# === Track0: locomotion ===
	# CRITICAL: 如果当前 action 是 FULLBODY_EXCLUSIVE，跳过 locomotion 更新
	var skip_loco_update: bool = (_cur_action_mode == MODE_FULLBODY_EXCLUSIVE or action_state == &"Die")

	if not skip_loco_update:
		var target_loco: StringName = LOCO_ANIM.get(loco_state, &"chain_/idle")
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
				var target_loco: StringName = LOCO_ANIM.get(loco_state, &"chain_/idle")
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
			target_action = &"chain_/fuse_progress"
			action_mode = MODE_FULLBODY_EXCLUSIVE
		elif action_state == &"Hurt":
			if _player.action_fsm != null and _player.action_fsm.has_method("should_use_fuse_hurt_anim") and _player.action_fsm.should_use_fuse_hurt_anim():
				target_action = &"chain_/fuse_hurt"
			else:
				target_action = &"chain_/hurt"
			action_mode = MODE_OVERLAY_UPPER
		elif action_state == &"Die":
			target_action = &"chain_/die"
			action_mode = MODE_FULLBODY_EXCLUSIVE
		
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
				target_action = &"chain_/anim_chain_cancel_R" if side == "R" else &"chain_/anim_chain_cancel_L"
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
				target_action = &"chain_/chain_R" if action_state == &"Attack_R" else &"chain_/chain_L"
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
		if _gf_mode and anim_name.begins_with("ghost_fist_/attack_"):
			if _cur_action_anim == anim_name:
				_cur_loco_anim = &""
			return

		# === P0 FIX: FULLBODY_EXCLUSIVE 动画播放在 track0，完成事件应走 ACTION 分发 ===
		if _cur_action_mode == MODE_FULLBODY_EXCLUSIVE and _cur_action_anim == anim_name:
			# die 是终态：不清空、不恢复、不发事件
			if anim_name == &"chain_/die" or anim_name == &"ghost_fist_/die":
				return
			if anim_name == &"ghost_fist_/hurt" and _ghost_fist != null and _ghost_fist.has_method("on_hurt_animation_finished"):
				_ghost_fist.on_hurt_animation_finished()
			var action_event: StringName = ACTION_END_MAP.get(anim_name, &"")
			if action_event != &"":
				_player.on_action_anim_end(action_event)
			# FULLBODY 结束：先恢复字段（后续 on_animation_complete 可能触发新动画，不能被覆盖）
			_cur_action_anim = &""
			_cur_action_mode = -1
			_cur_loco_anim = &""
			return

		# 普通 locomotion 完成（jump_up / jump_down 等非 loop 动画）
		var event: StringName = LOCO_END_MAP.get(anim_name, &"")
		if event != &"":
			_player.on_loco_anim_end(event)
		_cur_loco_anim = &""

	elif track == TRACK_ACTION:
		# === 清除手动 chain 动画标志 ===
		if anim_name in [&"chain_/chain_R", &"chain_/chain_L", &"chain_/anim_chain_cancel_R", &"chain_/anim_chain_cancel_L"]:
			_manual_chain_anim = false

		var event: StringName = ACTION_END_MAP.get(anim_name, &"")
		if event != &"" and _player != null:
			_player.on_action_anim_end(event)

		# die 是终态，不清空 _cur_action_anim，防止下一帧重新播放
		if anim_name != &"chain_/die" and anim_name != &"ghost_fist_/die":
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
	if _driver == null or _player == null:
		return

	# 死亡态硬闸：不允许再触发 chain 动画覆盖 die
	if _player.get_action_state() == &"Die":
		return
	if _player.health != null and _player.health.hp <= 0:
		return
	
	# 根据 slot 确定动画名
	var anim_name: StringName = &"chain_/chain_R" if slot_idx == 0 else &"chain_/chain_L"
	
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
		anim_name = &"chain_/anim_chain_cancel_R"
	elif left_active:
		anim_name = &"chain_/anim_chain_cancel_L"
	else:
		return

	_manual_chain_anim = true
	_cur_action_anim = anim_name
	_cur_action_mode = MODE_OVERLAY_UPPER
	_driver.play(TRACK_ACTION, anim_name, false)
	_log_play(TRACK_ACTION, anim_name, false)


# ── GF locomotion: loco_state → 基础键 ──
const GF_BASE_LOCO: Dictionary = {
	&"Idle": &"idle",
	&"Walk": &"walk",
	&"Run": &"run",
	&"Jump_up": &"jump_up",
	&"Jump_loop": &"jump_loop",
	&"Jump_down": &"jump_down",
}

# ── GF locomotion 映射 ──
const GF_LOCO_MAP: Dictionary = {
	&"idle": &"ghost_fist_/idle",
	&"walk": &"ghost_fist_/walk",
	&"run": &"ghost_fist_/run",
	&"jump_up": &"ghost_fist_/jump_up",
	&"jump_loop": &"ghost_fist_/jump_loop",
	&"jump_down": &"ghost_fist_/jump_down",
}

func _get_gf_loco_anim(base_key: StringName) -> StringName:
	return GF_LOCO_MAP.get(base_key, &"ghost_fist_/idle")


# ── 日志 ──
func _log_play(track: int, anim_name: StringName, loop: bool) -> void:
	if _player != null and _player.has_method("log_msg"):
		_player.log_msg("ANIM", "play track=%d name=%s loop=%s" % [track, anim_name, str(loop)])

func _log_end(track: int, anim_name: StringName) -> void:
	if _player != null and _player.has_method("log_msg"):
		_player.log_msg("ANIM", "end track=%d name=%s" % [track, anim_name])
