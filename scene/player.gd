class_name Player
extends CharacterBody2D

## Player 调度总线（Phase 0）
## 职责：缓存组件引用 / 固定 tick 顺序 / 输入转发 / 信号连接 / 统一日志
## tick 顺序: Movement → move_and_slide → LocomotionFSM → ChainSystem → ActionFSM → Animator

# ── 调试开关 ──
@export var debug_log: bool = true

# ── 移动参数 ──
@export var move_speed: float = 260.0
@export var run_speed_mult: float = 1.5
@export var jump_speed: float = 520.0
@export var gravity: float = 1500.0
@export var facing_visual_sign: float = 1.0

# ── 输入映射 ──
@export var action_left: StringName = &"move_left"
@export var action_right: StringName = &"move_right"
@export var action_jump: StringName = &"jump"
@export var action_chain_fire: StringName = &"chain_fire"
@export var action_chain_cancel: StringName = &"chain_cancel"
@export var action_fuse: StringName = &"chain_fuse"
@export var action_cancel_chains: StringName = &"chain_cancel"

# ── Phase 1: ChainSystem 配置参数 ──
@export_group("Chain System")
@export var chain_speed: float = 800.0
@export var rope_wave_amp: float = 15.0
@export var rope_segments: int = 24
@export var rope_damping: float = 0.92
@export var rope_gravity: float = 12.0
@export var rope_stiffness: float = 0.85
@export var rope_iterations: int = 3
@export var rope_wave_decay: float = 3.5
@export var rope_wave_freq: float = 2.8
@export var rope_wave_along_segments: float = 1.2
@export var rope_wave_hook_power: float = 2.2
@export var end_motion_inject: float = 0.6
@export var hand_motion_inject: float = 0.15
@export var texture_anchor_at_hook: bool = false

@export var chain_max_length: float = 350.0
@export var chain_max_fly_time: float = 0.5
@export var hold_time: float = 0.8
@export var burn_time: float = 0.5
@export var cancel_dissolve_time: float = 0.3
@export var fusion_chain_dissolve_time: float = 0.6
@export var fusion_lock_time: float = 0.4

@export var warn_start_ratio: float = 0.8
@export var warn_gamma: float = 2.0
@export var warn_color: Color = Color(1.0, 0.3, 0.3)

@export var spawn_try_up_count: int = 8
@export var spawn_try_up_step: float = 16.0
@export var spawn_try_side: float = 32.0

@export var chain_hit_mask: int = 1
@export var chain_interact_mask: int = 16

@export var hand_l_path: NodePath = NodePath("Visual/HandL")
@export var hand_r_path: NodePath = NodePath("Visual/HandR")
@export var chain_line0_path: NodePath = NodePath("Chains/ChainLine0")
@export var chain_line1_path: NodePath = NodePath("Chains/ChainLine1")
@export var chain_shader_path: String = "res://shaders/chain_sand_dissolve.gdshader"

const DEFAULT_CHAIN_SHADER_PATH: String = "res://shaders/chain_sand_dissolve.gdshader"

# ── 运行时状态 ──
var facing: int = 1
var jump_request: bool = false
var anim_fsm = null  # 由 Animator 设置（Phase 1: ChainSystem 需要）

# ── 组件引用 ──
var movement: PlayerMovement = null
var loco_fsm: PlayerLocomotionFSM = null
var action_fsm: PlayerActionFSM = null
var chain_sys = null  # Phase0: PlayerChainSystemStub; Phase1+: PlayerChainSystem
var health: PlayerHealth = null
var animator: PlayerAnimator = null
var weapon_controller: WeaponController = null


func _ready() -> void:
	add_to_group("player")
	if has_node("Visual/SpineSprite"):
			var test = load("res://scene/components/spine_quick_test.gd")
			test.run($Visual/SpineSprite)
	# 缓存组件
	movement = $Components/Movement as PlayerMovement
	loco_fsm = $Components/LocomotionFSM as PlayerLocomotionFSM
	action_fsm = $Components/ActionFSM as PlayerActionFSM
	chain_sys = $Components/ChainSystem  # 不强转类型，兼容 stub 与完整版
	health = $Components/Health as PlayerHealth
	animator = $Animator as PlayerAnimator
	weapon_controller = $Components/WeaponController as WeaponController

	# 安全检查
	var ok: bool = true
	if movement == null: push_error("[Player] Movement missing"); ok = false
	if loco_fsm == null: push_error("[Player] LocomotionFSM missing"); ok = false
	if action_fsm == null: push_error("[Player] ActionFSM missing"); ok = false
	if chain_sys == null: push_error("[Player] ChainSystem missing"); ok = false
	if health == null: push_error("[Player] Health missing"); ok = false
	if animator == null: push_error("[Player] Animator missing"); ok = false
	if weapon_controller == null: push_error("[Player] WeaponController missing"); ok = false

	if not ok:
		set_physics_process(false)
		return

	# setup 注入
	movement.setup(self)
	loco_fsm.setup(self)
	action_fsm.setup(self)
	weapon_controller.setup(self)
	if chain_sys.has_method("setup"):
		chain_sys.call("setup", self)
	if health.has_method("setup"):
		health.call("setup", self)
	animator.setup(self)

	# 信号连接: Health.damage_applied → ActionFSM.on_damaged
	if health.has_signal("damage_applied"):
		health.damage_applied.connect(_on_health_damage_applied)

	log_msg("BUS", "ready ok — tick order: Movement→move_and_slide→Loco→Chain→Action→Animator")


func _physics_process(dt: float) -> void:
	# === 1) Movement: 水平/重力/消费 jump ===
	movement.tick(dt)

	# === 2) move_and_slide: 物理更新（is_on_floor 之后才准确）===
	move_and_slide()

	# === 3) LocomotionFSM: 读取 floor/vy/intent，评估转移 ===
	loco_fsm.tick(dt)

	# === 4) ChainSystem: slot 更新 ===
	if chain_sys.has_method("tick"):
		chain_sys.call("tick", dt)

	# === 5) ActionFSM: 全局检查 + 动作状态 ===
	action_fsm.tick(dt)

	# === 6) Health: 无敌帧/击退 ===
	if health != null:
		health.tick(dt)

	# === 7) Animator: 裁决 + 播放 ===
	animator.tick(dt)


# ── 输入转发 ──

func _unhandled_input(event: InputEvent) -> void:
	# W / jump → LocomotionFSM
	if _is_action_just_pressed(event, action_jump, KEY_W):
		loco_fsm.on_w_pressed()
		return

	# 鼠标左键 / chain_fire → ActionFSM
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			action_fsm.on_m_pressed()
			return

	if _is_action_just_pressed(event, action_chain_fire, KEY_F):
		action_fsm.on_m_pressed()
		return

	# X / chain_cancel → ActionFSM
	if _is_action_just_pressed(event, action_chain_cancel, KEY_X):
		action_fsm.on_x_pressed()
		return
	
	# Z / weapon_switch → WeaponController + ActionFSM
	if event is InputEventKey:
		var ek: InputEventKey = event as InputEventKey
		if ek.pressed and ek.keycode == KEY_Z:
			if weapon_controller != null:
				weapon_controller.switch_weapon()
				# 硬切：中断当前动作
				if action_fsm != null:
					action_fsm.on_weapon_switched()
			return


# ── Animator → FSM 回调转发 ──

func on_loco_anim_end(event: StringName) -> void:
	match event:
		&"anim_end_jump_up":
			loco_fsm.on_anim_end_jump_up()
		&"anim_end_jump_down":
			loco_fsm.on_anim_end_jump_down()

func on_action_anim_end(event: StringName) -> void:
	match event:
		&"anim_end_attack":
			action_fsm.on_anim_end_attack()
		&"anim_end_attack_cancel":
			action_fsm.on_anim_end_attack_cancel()
		&"anim_end_hurt":
			action_fsm.on_anim_end_hurt()


# ── Health 信号 ──

func _on_health_damage_applied(_amount: int, _source_pos: Vector2) -> void:
	action_fsm.on_damaged()


# ── 供 FSM/Animator 读取的接口 ──

func get_locomotion_state() -> StringName:
	return loco_fsm.state_name() if loco_fsm != null else &"Idle"

func get_action_state() -> StringName:
	return action_fsm.state_name() if action_fsm != null else &"None"

func is_horizontal_input_locked() -> bool:
	if action_fsm != null and action_fsm.state == PlayerActionFSM.State.DIE:
		return true
	if health != null and health.is_knockback_active():
		return true
	return false

func is_player_locked() -> bool:
	if action_fsm != null and action_fsm.state == PlayerActionFSM.State.DIE:
		return true
	return false

func set_player_locked(_locked: bool) -> void:
	# Phase 1: ChainSystem 融合时需要此方法
	# 目前只是占位，未来可能需要更复杂的锁定逻辑
	pass

func apply_damage(amount: int, source_global_pos: Vector2) -> void:
	if health != null:
		health.apply_damage(amount, source_global_pos)

func heal(amount: int) -> void:
	if health != null:
		health.heal(amount)


# ── 统一日志 ──

func log_msg(source: String, msg: String) -> void:
	if not debug_log:
		return
	var f: int = Engine.get_physics_frames()
	var l_str: String = loco_fsm.state_name() if loco_fsm != null else "?"
	var a_str: String = action_fsm.state_name() if action_fsm != null else "?"
	var floor_str: String = str(is_on_floor())
	var vy_str: String = "%.1f" % velocity.y
	var intent_str: String = movement.intent_name() if movement != null else "?"
	var hp_val: int = health.hp if health != null else 0
	var sr: String = str(chain_sys.slot_R_available) if chain_sys != null and "slot_R_available" in chain_sys else "?"
	var sl: String = str(chain_sys.slot_L_available) if chain_sys != null and "slot_L_available" in chain_sys else "?"
	print("[F:%d][L:%s][A:%s] floor=%s vy=%s intent=%s hp=%d sR=%s sL=%s | [%s] %s" % [
		f, l_str, a_str, floor_str, vy_str, intent_str, hp_val, sr, sl, source, msg])


# ── 输入辅助 ──

func _is_action_just_pressed(event: InputEvent, action: StringName, fallback_key: int) -> bool:
	if action != &"" and InputMap.has_action(action):
		if event.is_action_pressed(action):
			return true
		return false
	if event is InputEventKey:
		var ek: InputEventKey = event as InputEventKey
		if ek.pressed and not ek.echo and ek.keycode == fallback_key:
			return true
	return false
