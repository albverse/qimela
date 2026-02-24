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
@export var facing_visual_sign: float = -1.0

# ── 输入映射 ──
@export var action_left: StringName = &"move_left"
@export var action_right: StringName = &"move_right"
@export var action_jump: StringName = &"jump"
@export var action_chain_fire: StringName = &"chain_fire"
@export var action_chain_cancel: StringName = &"cancel_chains"
@export var action_fuse: StringName = &"fuse"
@export var action_healing_burst: StringName = &"healing_burst"

# ── Phase 1: ChainSystem 配置参数 ──
@export_group("Chain System")
@export var chain_speed: float = 1500.0
@export var rope_wave_amp: float = 77.0
@export var rope_segments: int = 22
@export var rope_damping: float = 0.88
@export var rope_gravity: float = 0.0
@export var rope_stiffness: float = 1.7
@export var rope_iterations: int = 13
@export var rope_wave_decay: float = 7.5
@export var rope_wave_freq: float = 10.0
@export var rope_wave_along_segments: float = 8.0
@export var rope_wave_hook_power: float = 6.2
@export var end_motion_inject: float = 0.5
@export var hand_motion_inject: float = 0.15
@export var texture_anchor_at_hook: bool = true

@export var chain_max_length: float = 550.0
@export var chain_max_fly_time: float = 0.20
@export var hold_time: float = 0.5
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

@export_flags_2d_physics var chain_hit_mask: int = 9
@export_flags_2d_physics var chain_interact_mask = 64

@export var hand_l_path: NodePath = NodePath("Visual/HandL")
@export var hand_r_path: NodePath = NodePath("Visual/HandR")
@export var chain_line0_path: NodePath = NodePath("Chains/ChainLine0")
@export var chain_line1_path: NodePath = NodePath("Chains/ChainLine1")
@export var chain_shader_path: String = "res://shaders/chain_sand_dissolve.gdshader"

const DEFAULT_CHAIN_SHADER_PATH: String = "res://shaders/chain_sand_dissolve.gdshader"

# ── 运行时状态 ──
var facing: int = 1
var jump_request: bool = false
var _player_locked: bool = false
var _pending_chain_fire_side: String = ""  # "R" / "L" / ""
var _block_chain_fire_this_frame: bool = false

# ── 组件引用 ──
var movement: PlayerMovement = null
var loco_fsm: PlayerLocomotionFSM = null
var action_fsm: PlayerActionFSM = null
var chain_sys = null  # Phase0: PlayerChainSystemStub; Phase1+: PlayerChainSystem
var health: PlayerHealth = null
var animator: PlayerAnimator = null
var weapon_controller: WeaponController = null
var ghost_fist: GhostFist = null

# ── HealingSprite 持有与使用 ──
@export var max_healing_sprites: int = 3
@export var healing_per_sprite: int = 2
@export var healing_burst_light_energy: float = 5.0
@export var healing_burst_invincible_time: float = 0.2
@export var healing_burst_area_path: NodePath = NodePath("HealingBurstArea")
var _healing_slots: Array = [null, null, null]
var _healing_burst_area: Area2D = null
var _death_healing_cleanup_done: bool = false
var _death_chain_cleanup_done: bool = false


func _ready() -> void:
	if max_healing_sprites < 1:
		max_healing_sprites = 1
	_healing_slots.resize(max_healing_sprites)
	for i in range(max_healing_sprites):
		if _healing_slots[i] == null:
			continue
		if not is_instance_valid(_healing_slots[i]):
			_healing_slots[i] = null
	add_to_group("player")
	# 缓存组件
	movement = $Components/Movement as PlayerMovement
	loco_fsm = $Components/LocomotionFSM as PlayerLocomotionFSM
	action_fsm = $Components/ActionFSM as PlayerActionFSM
	chain_sys = $Components/ChainSystem  # 不强转类型，兼容 stub 与完整版
	health = $Components/Health as PlayerHealth
	animator = $Animator as PlayerAnimator
	weapon_controller = $Components/WeaponController as WeaponController
	_healing_burst_area = get_node_or_null(healing_burst_area_path) as Area2D

	# 安全检查
	var ok: bool = true
	if movement == null: push_error("[Player] Movement missing"); ok = false
	if loco_fsm == null: push_error("[Player] LocomotionFSM missing"); ok = false
	if action_fsm == null: push_error("[Player] ActionFSM missing"); ok = false
	if chain_sys == null: push_error("[Player] ChainSystem missing"); ok = false
	if health == null: push_error("[Player] Health missing"); ok = false
	if animator == null: push_error("[Player] Animator missing"); ok = false
	if weapon_controller == null: push_error("[Player] WeaponController missing"); ok = false
	if _healing_burst_area == null: push_warning("[Player] HealingBurstArea missing: %s" % healing_burst_area_path)

	if not ok:
		set_physics_process(false)
		return

	# Ghost Fist 引用（Visual 子节点）
	ghost_fist = get_node_or_null(^"Visual/GhostFist") as GhostFist
	if ghost_fist == null:
		push_warning("[Player] GhostFist not found under Visual — GhostFist weapon disabled")

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
	# Ghost Fist setup（在 animator.setup 之后）
	if ghost_fist != null:
		ghost_fist.setup(self)
		animator.setup_ghost_fist(ghost_fist)
		ghost_fist.state_changed.connect(_on_ghost_fist_state_changed)

	# 信号连接: Health.damage_applied → ActionFSM.on_damaged
	if health.has_signal("damage_applied"):
		health.damage_applied.connect(_on_health_damage_applied)

	log_msg("BUS", "ready ok — tick order: Movement→move_and_slide→Loco→Action→Health→Animator→Chain")


func _physics_process(dt: float) -> void:
	if action_fsm != null and action_fsm.state == PlayerActionFSM.State.DIE and not _death_chain_cleanup_done:
		if chain_sys != null and chain_sys.has_method("hard_clear_all_chains"):
			chain_sys.call("hard_clear_all_chains", "die_tick_guard")
		_death_chain_cleanup_done = true

	if action_fsm != null and action_fsm.state == PlayerActionFSM.State.DIE and not _death_healing_cleanup_done:
		_consume_all_healing_sprites_on_death()
		_death_healing_cleanup_done = true

	# === 1) Movement: 水平/重力/消费 jump ===
	movement.tick(dt)

	# === 2) move_and_slide: 物理更新（is_on_floor 之后才准确）===
	move_and_slide()

	# === 3) LocomotionFSM: 读取 floor/vy/intent，评估转移 ===
	loco_fsm.tick(dt)

	# === 4) ActionFSM: 全局检查 + 动作状态 ===
	action_fsm.tick(dt)

	# === 5) Health: 无敌帧/击退 ===
	if health != null:
		health.tick(dt)

	# === 6) Animator: 裁决 + 播放 ===
	animator.tick(dt)

	# === 7) ChainSystem: 在Animator之后更新，确保读取当帧骨骼锚点 ===
	if chain_sys.has_method("tick"):
		chain_sys.call("tick", dt)

	# === 8) 提交链条发射请求（延迟到状态机/血量更新之后，避免同帧竞态） ===
	_commit_pending_chain_fire()
	_block_chain_fire_this_frame = false


func _is_chain_fire_blocked() -> bool:
	if _block_chain_fire_this_frame:
		return true
	if health != null and health.hp <= 0:
		return true
	if action_fsm != null:
		if action_fsm.state == PlayerActionFSM.State.DIE or action_fsm.state == PlayerActionFSM.State.HURT:
			return true
	return false


func _commit_pending_chain_fire() -> void:
	if _pending_chain_fire_side == "":
		return
	if action_fsm != null and action_fsm.has_method("state_name") and action_fsm.state_name() == &"Die":
		_pending_chain_fire_side = ""
		return
	if chain_sys == null:
		_pending_chain_fire_side = ""
		return
	if _is_chain_fire_blocked():
		if has_method("log_msg"):
			log_msg("INPUT", "M_pressed: Chain request dropped (blocked state)")
		_pending_chain_fire_side = ""
		return
	if not chain_sys.has_method("pick_fire_slot"):
		_pending_chain_fire_side = ""
		return

	var expected_slot: int = 0 if _pending_chain_fire_side == "R" else 1
	var current_slot: int = chain_sys.pick_fire_slot()
	if current_slot != expected_slot:
		if has_method("log_msg"):
			log_msg("INPUT", "M_pressed: Chain request dropped (slot no longer available)")
		_pending_chain_fire_side = ""
		return

	chain_sys.fire(_pending_chain_fire_side)
	if has_method("log_msg"):
		log_msg("INPUT", "M_pressed: Chain slot=%d fired (bypass ActionFSM, deferred)" % expected_slot)
	_pending_chain_fire_side = ""


# ── 输入转发 ──

func _unhandled_input(event: InputEvent) -> void:
	if action_fsm != null and action_fsm.state == PlayerActionFSM.State.DIE:
		return

	# C / use healing sprite
	if _is_action_just_pressed(event, &"use_healing", KEY_C):
		use_healing_sprite()
		return

	# Q / healing burst（测试入口）
	if _is_action_just_pressed(event, action_healing_burst, KEY_Q):
		use_healing_burst()
		return

	# Z / switch weapon
	if _is_action_just_pressed(event, &"", KEY_Z):
		if weapon_controller != null:
			var was_gf: bool = weapon_controller.is_ghost_fist()
			weapon_controller.switch_weapon()
			var is_gf: bool = weapon_controller.is_ghost_fist()
			# GhostFist exit → enter 转换
			if was_gf and not is_gf:
				_deactivate_ghost_fist()
			if action_fsm != null and action_fsm.has_method("on_weapon_switched"):
				action_fsm.on_weapon_switched()
			if not was_gf and is_gf:
				_activate_ghost_fist()
		return

	# Space / fuse
	if _is_action_just_pressed(event, action_fuse, KEY_SPACE):
		var is_chain_for_fuse: bool = (
			weapon_controller != null
			and weapon_controller.current_weapon == weapon_controller.WeaponType.CHAIN
		)
		if is_chain_for_fuse and action_fsm != null and action_fsm.has_method("on_space_pressed"):
			action_fsm.on_space_pressed()
		return

	# W / jump → LocomotionFSM
	if _is_action_just_pressed(event, action_jump, KEY_W):
		loco_fsm.on_w_pressed()
		return

	# === HANDOFF 推荐方案：Chain 绕过 ActionFSM，作为 overlay ===
	# 鼠标左键 / chain_fire
	var is_m_pressed: bool = false
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			is_m_pressed = true
	
	if not is_m_pressed and _is_action_just_pressed(event, action_chain_fire, KEY_F):
		is_m_pressed = true
	
	if is_m_pressed:
		# === Ghost Fist 专用路径 ===
		if weapon_controller != null and weapon_controller.is_ghost_fist():
			_on_ghost_fist_attack_input()
			return

		# 检查当前武器是否为 Chain
		var is_chain: bool = (weapon_controller != null and
							  weapon_controller.current_weapon == weapon_controller.WeaponType.CHAIN)

		if is_chain:
			# 若当前槽位已链接奇美拉，优先触发互动（不进入融合/再发射流程）
			if chain_sys != null:
				var slot: int = chain_sys.active_slot
				if slot >= 0 and slot < chain_sys.chains.size():
					var active_chain = chain_sys.chains[slot]
					if active_chain != null and active_chain.state == chain_sys.ChainState.LINKED and active_chain.is_chimera:
						var chimera: Node = active_chain.linked_target
						if chimera != null and is_instance_valid(chimera) and chimera.has_method("on_player_interact"):
							chimera.call("on_player_interact", self)
							if has_method("log_msg"):
								log_msg("INPUT", "M_pressed: chimera interact on active slot=%d" % slot)
							return

			# === Chain 专用路径：不经过 ActionFSM ===
			# 1. 检查是否可以发射（死亡/受伤/本帧受击拒绝）
			if _is_chain_fire_blocked():
				return
			
			# 2. 从 ChainSystem 获取可用 slot
			if chain_sys != null and chain_sys.has_method("pick_fire_slot"):
				var slot: int = chain_sys.pick_fire_slot()
				if slot >= 0:
					# 3. 延迟到 physics tick 末尾提交，避免同帧与 damaged/Die 竞态
					var side: String = "R" if slot == 0 else "L"
					_pending_chain_fire_side = side
					
					if has_method("log_msg"):
						log_msg("INPUT", "M_pressed: Chain slot=%d queued (bypass ActionFSM)" % slot)
					return
			
			# 没有可用 slot，忽略
			if has_method("log_msg"):
				log_msg("INPUT", "M_pressed: Chain no available slot")
			return
		else:
			# === 非 Chain 武器：走 ActionFSM 标准流程 ===
			action_fsm.on_m_pressed()
			return

	# X / chain_cancel
	if _is_action_just_pressed(event, action_chain_cancel, KEY_X):
		var is_chain: bool = (weapon_controller != null and 
							  weapon_controller.current_weapon == weapon_controller.WeaponType.CHAIN)
		
		if is_chain and chain_sys != null:
			# Chain专用路径：先播放取消动画，再溶解链条
			if chain_sys.has_method("force_dissolve_all_chains"):
				# 检查哪些链条活跃
				var right_active: bool = (chain_sys.chains.size() > 0 and 
										 chain_sys.chains[0].state != chain_sys.ChainState.IDLE and 
										 chain_sys.chains[0].state != chain_sys.ChainState.DISSOLVING)
				var left_active: bool = (chain_sys.chains.size() > 1 and 
										chain_sys.chains[1].state != chain_sys.ChainState.IDLE and 
										chain_sys.chains[1].state != chain_sys.ChainState.DISSOLVING)
				
				# 先播放取消动画
				if (right_active or left_active) and animator != null and animator.has_method("play_chain_cancel"):
					animator.play_chain_cancel(right_active, left_active)
				
				# 延迟溶解，给动画播放时间
				var tw: Tween = create_tween()
				tw.tween_interval(0.25)  # 取消动画时长
				tw.tween_callback(func() -> void:
					if chain_sys != null:
						chain_sys.force_dissolve_all_chains()
				)
				
				if has_method("log_msg"):
					log_msg("INPUT", "X_pressed: Chain cancel with animation")
			return
		else:
			# 非Chain武器：走ActionFSM标准流程
			action_fsm.on_x_pressed()
			return

# ── Ghost Fist 管理 ──

func _activate_ghost_fist() -> void:
	if ghost_fist == null:
		return
	ghost_fist.activate()
	if animator != null:
		animator.set_gf_mode(true)
		animator.play_ghost_fist_enter()
	log_msg("WEAPON", "GhostFist ACTIVATED → GF_ENTER")


func _deactivate_ghost_fist() -> void:
	if ghost_fist == null:
		return
	ghost_fist.deactivate()
	if animator != null:
		animator.play_ghost_fist_exit()
		# GF exit 动画播放后由 on_animation_complete 切 gf_mode = false
		# 这里延迟关闭 gf_mode 以让 exit 动画播放完
		var tw: Tween = create_tween()
		tw.tween_interval(0.5)
		tw.tween_callback(func() -> void:
			if animator != null:
				animator.set_gf_mode(false)
		)
	log_msg("WEAPON", "GhostFist DEACTIVATED → GF_EXIT")


func _on_ghost_fist_attack_input() -> void:
	if ghost_fist == null:
		return
	if action_fsm != null and action_fsm.state == PlayerActionFSM.State.DIE:
		return
	if action_fsm != null and action_fsm.state == PlayerActionFSM.State.HURT:
		return
	# 由 GhostFist.state_changed 信号统一驱动 Animator 播放
	ghost_fist.on_attack_input()


func _on_ghost_fist_state_changed(new_state: int, context: StringName) -> void:
	## 由 GhostFist.state_changed 信号触发
	## 处理 combo_check → 续段攻击 或 cooldown 的动画播放
	if animator == null:
		return
	match new_state:
		GhostFist.GFState.GF_ATTACK_1, GhostFist.GFState.GF_ATTACK_2, \
		GhostFist.GFState.GF_ATTACK_3, GhostFist.GFState.GF_ATTACK_4:
			var stage: int = new_state - GhostFist.GFState.GF_ATTACK_1 + 1
			animator.play_ghost_fist_attack(stage)
			log_msg("GF", "combo → stage=%d" % stage)
		GhostFist.GFState.GF_COOLDOWN:
			animator.play_ghost_fist_cooldown()
			log_msg("GF", "→ cooldown")


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
		&"anim_end_fuse":
			if action_fsm.has_method("on_anim_end_fuse"):
				action_fsm.on_anim_end_fuse()


# ── Health 信号 ──

func _on_health_damage_applied(_amount: int, _source_pos: Vector2) -> void:
	_block_chain_fire_this_frame = true
	_pending_chain_fire_side = ""
	action_fsm.on_damaged()


# ── 供 FSM/Animator 读取的接口 ──

func get_locomotion_state() -> StringName:
	return loco_fsm.state_name() if loco_fsm != null else &"Idle"

func get_action_state() -> StringName:
	return action_fsm.state_name() if action_fsm != null else &"None"

func is_horizontal_input_locked() -> bool:
	if _player_locked:
		return true
	if action_fsm != null and action_fsm.state == PlayerActionFSM.State.DIE:
		return true
	if health != null and health.is_knockback_active():
		return true
	return false

func is_player_locked() -> bool:
	if _player_locked:
		return true
	if action_fsm != null and action_fsm.state == PlayerActionFSM.State.DIE:
		return true
	return false

func set_player_locked(locked: bool) -> void:
	_player_locked = locked

func apply_damage(amount: int, source_global_pos: Vector2) -> void:
	if health != null:
		health.apply_damage(amount, source_global_pos)

func heal(amount: int) -> void:
	if health != null:
		health.heal(amount)


## apply_stun(seconds): 僵直效果 — 禁止输入/动作持续 seconds 秒，不扣血
## 由外部（如 ChimeraStoneSnake 子弹）调用
func apply_stun(seconds: float) -> void:
	if seconds <= 0.0:
		return
	if action_fsm != null and action_fsm.state == PlayerActionFSM.State.DIE:
		return
	# 通过 ActionFSM 进入 Hurt 状态来实现僵直（不扣血）
	if action_fsm != null:
		action_fsm.on_stunned(seconds)
	if has_method("log_msg"):
		log_msg("STUN", "apply_stun %.2fs" % seconds)


# ── HealingSprite 接口（供 healing_sprite.gd 调用）──

func try_collect_healing_sprite(sprite: Node, preferred_slot: int = -1) -> int:
	if sprite == null or not is_instance_valid(sprite):
		return -1
	for i in range(max_healing_sprites):
		if _healing_slots[i] == sprite:
			return i

	var picked: int = -1
	if preferred_slot >= 0 and preferred_slot < max_healing_sprites and _healing_slots[preferred_slot] == null:
		picked = preferred_slot
	else:
		for i in range(max_healing_sprites):
			if _healing_slots[i] == null:
				picked = i
				break

	if picked == -1:
		return -1

	_healing_slots[picked] = sprite
	if has_method("log_msg"):
		log_msg("HEAL", "collect sprite slot=%d count=%d" % [picked, _healing_count()])
	return picked


func remove_healing_sprite(sprite: Node) -> void:
	if sprite == null:
		return
	for i in range(max_healing_sprites):
		if _healing_slots[i] == sprite:
			_healing_slots[i] = null


func get_healing_orbit_center_global(index: int) -> Vector2:
	if index <= 0 and has_node("Visual/center1"):
		return (get_node("Visual/center1") as Node2D).global_position
	if index == 1 and has_node("Visual/center2"):
		return (get_node("Visual/center2") as Node2D).global_position
	if has_node("Visual/center3"):
		return (get_node("Visual/center3") as Node2D).global_position
	return global_position


func use_healing_sprite() -> bool:
	if action_fsm != null and action_fsm.state == PlayerActionFSM.State.DIE:
		return false
	for i in range(max_healing_sprites):
		var sp: Node = _healing_slots[i]
		if sp != null and is_instance_valid(sp):
			_healing_slots[i] = null
			if sp.has_method("consume"):
				sp.call("consume")
			heal(healing_per_sprite)
			if has_method("log_msg"):
				log_msg("HEAL", "use sprite slot=%d heal=%d remain=%d" % [i, healing_per_sprite, _healing_count()])
			return true
	return false


func use_healing_burst() -> bool:
	if action_fsm != null and action_fsm.state == PlayerActionFSM.State.DIE:
		return false
	var current_count: int = _healing_count()
	if current_count < max_healing_sprites:
		if has_method("log_msg"):
			log_msg("HEAL", "治愈精灵不足，无法触发大爆炸（当前：%d/%d）" % [current_count, max_healing_sprites])
		return false

	if _healing_burst_area == null:
		_healing_burst_area = get_node_or_null(healing_burst_area_path) as Area2D
	if _healing_burst_area == null:
		push_warning("[Player] HealingBurstArea missing, skip burst stun")

	for i in range(max_healing_sprites):
		var sp: Node = _healing_slots[i]
		if sp == null or not is_instance_valid(sp):
			continue
		_healing_slots[i] = null
		if sp.has_method("consume"):
			sp.call("consume")

	if has_method("log_msg"):
		log_msg("HEAL", "治愈精灵大爆炸！")

	if health != null and health.has_method("grant_invincible"):
		health.grant_invincible(healing_burst_invincible_time)
		if has_method("log_msg"):
			log_msg("HEAL", "healing_burst grant invincible=%.2fs" % healing_burst_invincible_time)

	if _healing_burst_area != null:
		var bodies: Array[Node2D] = _healing_burst_area.get_overlapping_bodies()
		for body in bodies:
			var monster: MonsterBase = body as MonsterBase
			if monster != null and monster.has_method("apply_healing_burst_stun"):
				monster.apply_healing_burst_stun()
				if has_method("log_msg"):
					log_msg("HEAL", "healing_burst stun hit=%s" % monster.name)
	if EventBus != null and EventBus.has_method("emit_healing_burst"):
		EventBus.emit_healing_burst(healing_burst_light_energy)
	if has_method("log_msg"):
		log_msg("HEAL", "释放全场光照能量：%.2f" % healing_burst_light_energy)
	return true


func _healing_count() -> int:
	var n: int = 0
	for i in range(max_healing_sprites):
		if _healing_slots[i] != null and is_instance_valid(_healing_slots[i]):
			n += 1
	return n


func _consume_all_healing_sprites_on_death() -> void:
	for i in range(max_healing_sprites):
		var sp: Node = _healing_slots[i]
		if sp == null or not is_instance_valid(sp):
			_healing_slots[i] = null
			continue
		_healing_slots[i] = null
		if sp.has_method("consume_on_death"):
			sp.call("consume_on_death")
		elif sp.has_method("consume"):
			sp.call("consume")
	if has_method("log_msg"):
		log_msg("HEAL", "clear all healing sprites on die")


func on_die_entered() -> void:
	_pending_chain_fire_side = ""
	_block_chain_fire_this_frame = true
	if chain_sys != null and chain_sys.has_method("hard_clear_all_chains"):
		chain_sys.call("hard_clear_all_chains", "die_enter")


# ── 统一日志 ──

func log_msg(source: String, msg: String) -> void:
	if not debug_log:
		return
	var f: int = Engine.get_physics_frames()
	var l_str: String = String(loco_fsm.state_name()) if loco_fsm != null else "?"
	var a_str: String = String(action_fsm.state_name()) if action_fsm != null else "?"
	var floor_str: String = str(is_on_floor())
	var vy_str: String = "%.1f" % velocity.y
	var intent_str: String = String(movement.intent_name()) if movement != null else "?"
	var hp_val: int = health.hp if health != null else 0
	var sr: String = str(chain_sys.slot_R_available) if chain_sys != null and "slot_R_available" in chain_sys else "?"
	var sl: String = str(chain_sys.slot_L_available) if chain_sys != null and "slot_L_available" in chain_sys else "?"
	print("[F:%d][L:%s][A:%s] floor=%s vy=%s intent=%s hp=%d sR=%s sL=%s | [%s] %s" % [
		f, l_str, a_str, floor_str, vy_str, intent_str, hp_val, sr, sl, source, msg])


# ── 输入辅助 ──

func _is_action_just_pressed(event: InputEvent, action: StringName, fallback_key: int) -> bool:
	if action != &"" and InputMap.has_action(action):
		if event.is_action_pressed(action):
			if event is InputEventKey and (event as InputEventKey).echo:
				return false
			return true
		return false
	if event is InputEventKey:
		var ek: InputEventKey = event as InputEventKey
		if ek.pressed and not ek.echo and ek.keycode == fallback_key:
			return true
	return false
