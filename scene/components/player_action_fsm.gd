extends Node
class_name PlayerActionFSM

## ActionFSM（动作覆盖层）
## 状态：None / Attack / AttackCancel / Hurt / Die
## 攻击分为左右手（side: R/L）存储在单独变量
## 全局：Die(pr=100) > Hurt(pr=90)
## GREEN：Attack/Cancel → Walk/Run (pr=50/51) 允许动作中移动
## 动作结束统一走 resolve_post_action_state
## 禁止：播放动画、改 velocity

enum State { NONE, ATTACK, ATTACK_CANCEL, HURT, DIE }

const STATE_NAMES: Array[StringName] = [
	&"None", &"Attack", &"AttackCancel", &"Hurt", &"Die"
]

var state: int = State.NONE
var attack_side: String = ""  # "R" / "L" / "" - 当前攻击使用的手（仅Attack/AttackCancel时有效）
var _player: CharacterBody2D = null
var _weapon_controller: WeaponController = null

## Phase 0 修复：延迟 fire 提交，防止幽灵发射
var _pending_fire_side: String = ""  # "R" / "L" / ""

## 开关：是否允许移动打断动作（默认 false = 移动不取消链）
var allow_move_interrupt_action: bool = false

## S3: 卡死保护 - 超时强制 resolver
var _attack_timeout: float = 2.0  # 2秒超时
var _attack_timer: float = 0.0    # 当前计时器
var _hurt_timeout: float = 1.0    # Hurt 超时（1秒）
var _hurt_timer: float = 0.0


func state_name() -> StringName:
	var base_name: StringName = STATE_NAMES[state] if state >= 0 and state < STATE_NAMES.size() else &"?"
	# Attack/AttackCancel 加上 side 后缀以便日志清晰
	if state == State.ATTACK and attack_side != "":
		return StringName(String(base_name) + "_" + attack_side)
	elif state == State.ATTACK_CANCEL and attack_side != "":
		return StringName(String(base_name) + "_" + attack_side)
	return base_name


func setup(player: CharacterBody2D) -> void:
	_player = player
	_weapon_controller = player.weapon_controller if player != null else null
	state = State.NONE


## _compute_context: 计算当前上下文（用于武器动画选择）
## 返回: "ground_idle" / "ground_move" / "air"
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


func tick(_dt: float) -> void:
	if _player == null:
		return
	
	# === CRITICAL FIX: DIE 最高优先级检查（必须在 pending fire 之前）===
	if state == State.DIE:
		_pending_fire_side = ""  # 死亡时清空挂起的发射
		_attack_timer = 0.0
		return  # 终态：不执行任何逻辑

	# === GLOBAL pr=100: hp<=0 → Die ===
	var hp: int = _player.health.hp if _player.health != null else 1
	if hp <= 0 and state != State.DIE:
		_pending_fire_side = ""  # 清空挂起的发射
		_attack_timer = 0.0
		_do_transition(State.DIE, "hp<=0", 100)
		return
	
	# === S3: 超时保护（Attack）===
	if state == State.ATTACK or state == State.ATTACK_CANCEL:
		_attack_timer += _dt
		if _attack_timer > _attack_timeout:
			if _player.has_method("log_msg"):
				_player.log_msg("ACTION", "TIMEOUT! Attack stuck for %.2fs, forcing resolver (side=%s)" % [_attack_timer, attack_side])
			
			# 强制归还 slot
			if attack_side != "" and _player.chain_sys != null:
				if _player.chain_sys.has_method("release"):
					_player.chain_sys.release(attack_side)
			
			# 强制 resolver
			_attack_timer = 0.0
			_resolve_and_transition("timeout_protection")
			return
	else:
		_attack_timer = 0.0
	
	# === S3: 超时保护（Hurt）===
	if state == State.HURT:
		_hurt_timer += _dt
		if _hurt_timer > _hurt_timeout:
			if _player.has_method("log_msg"):
				_player.log_msg("ACTION", "TIMEOUT! Hurt stuck for %.2fs, forcing resolver" % _hurt_timer)
			_hurt_timer = 0.0
			_resolve_and_transition("hurt_timeout_protection")
			return
	else:
		_hurt_timer = 0.0
	
	# === 延迟 fire 提交（状态门控，防幽灵发射）===
	# 只有在状态仍是 ATTACK 且 attack_side 匹配时才真正提交 fire
	if _pending_fire_side != "" and _player.chain_sys != null:
		if state == State.ATTACK and attack_side == "R" and _pending_fire_side == "R":
			_player.chain_sys.fire("R")
			_pending_fire_side = ""
		elif state == State.ATTACK and attack_side == "L" and _pending_fire_side == "L":
			_player.chain_sys.fire("L")
			_pending_fire_side = ""
		elif state != State.ATTACK:
			# 状态已经不是攻击态（同帧 damaged/X → Hurt/Die/Cancel），丢弃请求
			_pending_fire_side = ""


# ── 外部事件入口 ──

## 强制打断链条时释放 slot（避免泄漏）
func _abort_chain_if_active(reason: String) -> void:
	if _player == null or _player.chain_sys == null:
		return
	
	match state:
		State.ATTACK, State.ATTACK_CANCEL:
			if attack_side == "R":
				_player.chain_sys.cancel("R")
				if _player.has_method("log_msg"):
					_player.log_msg("ACTION", "abort_chain R reason=%s" % reason)
			elif attack_side == "L":
				_player.chain_sys.cancel("L")
				if _player.has_method("log_msg"):
					_player.log_msg("ACTION", "abort_chain L reason=%s" % reason)


## 强制释放槽位（用于 cancel 动画结束时确保 slot 不卡死）
func _force_release_slot(side: String) -> void:
	if _player == null or _player.chain_sys == null:
		return
	
	if _player.chain_sys.has_method("release"):
		_player.chain_sys.release(side)
	else:
		# 兜底：直接把槽位打回可用（如果 release 方法不存在）
		if side == "R":
			_player.chain_sys.slot_R_available = true
		elif side == "L":
			_player.chain_sys.slot_L_available = true
	
	if _player.has_method("log_msg"):
		_player.log_msg("ACTION", "force_release_slot(%s)" % side)


func on_damaged() -> void:
	if _player == null:
		return
	if state == State.DIE:
		return

	_log_event("damaged")
	
	# 清空挂起的发射（防止同帧 M+damaged 导致的幽灵 fire）
	_pending_fire_side = ""
	
	var hp: int = _player.health.hp if _player.health != null else 1
	
	# === hp<=0 → Die（清理逻辑已在_do_transition中统一处理）===
	if hp <= 0:
		_do_transition(State.DIE, "damaged->DIE(hp<=0)", 100)
		return
	
	# === hp>0 的情况：受伤 ===
	# 受伤会强制打断链条，先释放 slot
	if state in [State.ATTACK, State.ATTACK_CANCEL]:
		_abort_chain_if_active("damaged")
	
	_do_transition(State.HURT, "damaged->HURT", 90)


func on_m_pressed() -> void:
	if _player == null:
		return
	if state == State.DIE or state == State.HURT:
		return

	_log_event("M_pressed")

	# 已在动作中（Attack/Cancel）：忽略（不叠加）
	if state != State.NONE:
		return
	
	# === 委托式选动画：根据武器类型决定行为 ===
	if _weapon_controller == null:
		if _player.has_method("log_msg"):
			_player.log_msg("ACTION", "M_pressed FAILED: no weapon_controller")
		return
	
	var context: String = _compute_context()
	
	# Chain: 需要 slot 选择 R/L
	if _weapon_controller.current_weapon == _weapon_controller.WeaponType.CHAIN:
		var slot_r: bool = _player.chain_sys.slot_R_available if _player.chain_sys != null else true
		var slot_l: bool = _player.chain_sys.slot_L_available if _player.chain_sys != null else true
		
		if slot_r:
			attack_side = "R"
			_do_transition(State.ATTACK, "M_pressed policy=R", 5)
			_pending_fire_side = "R"
		elif slot_l:
			attack_side = "L"
			_do_transition(State.ATTACK, "M_pressed policy=L", 4)
			_pending_fire_side = "L"
		else:
			if _player.has_method("log_msg"):
				_player.log_msg("ACTION", "M_pressed policy=NONE (no slots)")
	
	# Sword: 不需要 slot，直接出招
	elif _weapon_controller.current_weapon == _weapon_controller.WeaponType.SWORD:
		attack_side = "R"  # Sword默认用R侧（语义上的主手）
		_do_transition(State.ATTACK, "M_pressed weapon=Sword context=%s" % context, 5)
		_pending_fire_side = ""
	
	# Knife: 不需要 slot，直接出招
	elif _weapon_controller.current_weapon == _weapon_controller.WeaponType.KNIFE:
		attack_side = "R"
		_do_transition(State.ATTACK, "M_pressed weapon=Knife context=%s" % context, 5)
		_pending_fire_side = ""


func on_x_pressed() -> void:
	if _player == null:
		return
	if state == State.DIE or state == State.HURT:
		return

	_log_event("X_pressed")
	
	# 清空挂起的发射（取消时不应再 fire）
	_pending_fire_side = ""

	# PINK pr=6: Attack → AttackCancel
	if state == State.ATTACK:
		_do_transition(State.ATTACK_CANCEL, "X_pressed", 6)
		# 保护：只在 slot 被占用时才 cancel（避免重复 cancel）
		if attack_side == "R" and _player.chain_sys != null and not _player.chain_sys.slot_R_available:
			_player.chain_sys.cancel("R")
		elif attack_side == "L" and _player.chain_sys != null and not _player.chain_sys.slot_L_available:
			_player.chain_sys.cancel("L")


func on_weapon_switched() -> void:
	"""武器切换（Z键）：硬切，中断当前动作"""
	if _player == null:
		return
	if state == State.DIE:
		return  # 死亡时不允许切换
	
	_log_event("weapon_switched")
	
	# 清空 pending fire
	_pending_fire_side = ""
	
	# 如果正在攻击中，取消链条
	if state == State.ATTACK or state == State.ATTACK_CANCEL:
		if attack_side == "R" and _player.chain_sys != null and not _player.chain_sys.slot_R_available:
			_player.chain_sys.cancel("R")
		elif attack_side == "L" and _player.chain_sys != null and not _player.chain_sys.slot_L_available:
			_player.chain_sys.cancel("L")
	
	# 强制停止 track1 动画（防止切换后仍播放旧动画）
	if _player.animator != null and _player.animator.has_method("force_stop_action"):
		_player.animator.force_stop_action()
	
	# 清空 attack_side
	attack_side = ""
	
	# 硬切回 None
	_do_transition(State.NONE, "weapon_switched", 99)


# ── anim_end 事件（由 Animator 通过 Player 转发）──

func on_anim_end_attack() -> void:
	_log_event("anim_end_attack")
	
	# === 检查武器类型：Chain 需要 release slot，Sword 不需要 ===
	var is_chain_weapon: bool = true
	if _weapon_controller != null:
		is_chain_weapon = (_weapon_controller.current_weapon == _weapon_controller.WeaponType.CHAIN)
	
	# Chain: 释放槽位
	if is_chain_weapon and attack_side != "":
		if state != State.ATTACK_CANCEL:
			if _player.chain_sys != null and _player.chain_sys.has_method("release"):
				_player.chain_sys.release(attack_side)
	
	# 只有仍在ATTACK状态时才需要resolver转移
	if state == State.ATTACK:
		_resolve_and_transition("anim_end_attack")
	else:
		# DEBUG: 状态不是 ATTACK，不转移
		if _player != null and _player.has_method("log_msg"):
			_player.log_msg("ACTION", "anim_end_attack SKIP: state=%s != ATTACK" % state_name())


func on_anim_end_attack_cancel() -> void:
	_log_event("anim_end_attack_cancel")
	# 强制释放 slot
	if attack_side != "":
		_force_release_slot(attack_side)
	if state == State.ATTACK_CANCEL:
		_resolve_and_transition("anim_end_attack_cancel")

func on_anim_end_hurt() -> void:
	_log_event("anim_end_hurt")
	if state == State.HURT:
		_resolve_and_transition("anim_end_hurt")


# ── Resolver（FAML resolve_post_action_state）──

func _resolve_and_transition(reason: String) -> void:
	var resolved: StringName = _resolve_post_action_state()

	if _player != null and _player.has_method("log_msg"):
		_player.log_msg("ACTION", "RESOLVER result=%s" % resolved)

	if resolved == &"Die":
		_do_transition(State.DIE, reason + "->resolver=Die", 100)
		return

	# locomotion 类结果 → ActionFSM 回 None（locomotion 由 LocomotionFSM 独立维护）
	_do_transition(State.NONE, reason + "->resolver=" + String(resolved), 2)

	# 通知 LocomotionFSM 同步到 resolver 建议的状态（可选：处理空中结束场景）
	if _player != null and _player.loco_fsm != null:
		_sync_loco_to_resolved(resolved)


func _resolve_post_action_state() -> StringName:
	if _player == null:
		return &"Idle"

	var hp: int = _player.health.hp if _player.health != null else 1
	if hp <= 0:
		return &"Die"

	var on_floor: bool = _player.is_on_floor()
	var vy: float = _player.velocity.y

	if not on_floor:
		if vy < 0.0:
			return &"Jump_up"
		else:
			return &"Jump_loop"

	var intent: int = _player.movement.move_intent if _player.movement != null else 0
	if intent == 2:  # Run
		return &"Run"
	if intent == 1:  # Walk
		return &"Walk"
	return &"Idle"


func _sync_loco_to_resolved(resolved: StringName) -> void:
	## 当 ActionFSM 结束动作时，如果 LocomotionFSM 的状态与 resolver 不一致
	## （例如在空中结束 chain 但 Loco 仍是地面态），强制同步
	var loco: PlayerLocomotionFSM = _player.loco_fsm
	if loco == null:
		return

	var target_state: int = -1
	match resolved:
		&"Idle": target_state = PlayerLocomotionFSM.State.IDLE
		&"Walk": target_state = PlayerLocomotionFSM.State.WALK
		&"Run": target_state = PlayerLocomotionFSM.State.RUN
		&"Jump_up": target_state = PlayerLocomotionFSM.State.JUMP_UP
		&"Jump_loop": target_state = PlayerLocomotionFSM.State.JUMP_LOOP
		&"Jump_down": target_state = PlayerLocomotionFSM.State.JUMP_DOWN
		&"Die": target_state = PlayerLocomotionFSM.State.DEAD

	if target_state >= 0 and loco.state != target_state:
		var from_name: StringName = loco.state_name()
		loco.state = target_state
		var to_name: StringName = loco.state_name()
		if _player.has_method("log_msg"):
			_player.log_msg("ACTION", "SYNC_LOCO %s->%s (resolver)" % [from_name, to_name])


func _sync_loco_to_state(state_name: StringName) -> void:
	## GREEN 转换专用：立即同步 LocomotionFSM 到指定状态
	var loco: PlayerLocomotionFSM = _player.loco_fsm
	if loco == null:
		return

	var target_state: int = -1
	match state_name:
		&"Idle": target_state = PlayerLocomotionFSM.State.IDLE
		&"Walk": target_state = PlayerLocomotionFSM.State.WALK
		&"Run": target_state = PlayerLocomotionFSM.State.RUN
		&"Jump_up": target_state = PlayerLocomotionFSM.State.JUMP_UP
		&"Jump_loop": target_state = PlayerLocomotionFSM.State.JUMP_LOOP
		&"Jump_down": target_state = PlayerLocomotionFSM.State.JUMP_DOWN
		&"Die": target_state = PlayerLocomotionFSM.State.DEAD

	if target_state >= 0 and loco.state != target_state:
		var from_name: StringName = loco.state_name()
		loco.state = target_state
		var to_name: StringName = loco.state_name()
		if _player.has_method("log_msg"):
			_player.log_msg("ACTION", "SYNC_LOCO %s->%s (GREEN)" % [from_name, to_name])


# ── 转移执行 ──

func _do_transition(to: int, reason: String, priority: int) -> void:
	var from_name: StringName = state_name()
	state = to
	var to_name: StringName = state_name()

	if from_name == to_name:
		return
	
	# === S3: 进入 ATTACK 重置计时器 ===
	if to == State.ATTACK or to == State.ATTACK_CANCEL:
		_attack_timer = 0.0
	
	# === CRITICAL FIX: 进入Die时的全局锁定与清理 ===
	if to == State.DIE and _player != null:
		# 0. 先清空pending fire（防止后续fire）
		if _pending_fire_side != "":
			if _player.has_method("log_msg"):
				_player.log_msg("CHAIN", "clear_pending_fire reason=die (was=%s)" % _pending_fire_side)
			_pending_fire_side = ""
		
		# 1. 死亡：立即清空所有链条（不走溶解，不依赖 tick/tween）
		if _player.chain_sys != null:
			if _player.chain_sys.has_method("hard_clear_all_chains"):
				_player.chain_sys.hard_clear_all_chains("die")
			else:
				# 旧版本fallback：至少把所有链条强制溶解（注意：若 player 被禁用处理，Tween 可能不会跑完）
				_player.chain_sys.force_dissolve_all_chains()

		# 2. 冻结movement（虽然movement自己也会检查Die，但这里主动冻结更保险）
		if _player.movement != null:
			_player.movement.move_intent = 0  # MoveIntent.NONE
			_player.movement.input_dir = 0.0
			_player.velocity.x = 0.0

	if _player != null and _player.has_method("log_msg"):
		_player.log_msg("ACTION",
			"TRANS=%s->%s reason=%s pr=%d" % [from_name, to_name, reason, priority])


# ── 日志 ──

func _log_event(event: String) -> void:
	if _player != null and _player.has_method("log_msg"):
		_player.log_msg("ACTION", "EVENT=%s" % event)
