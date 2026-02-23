extends Node
class_name PlayerActionFSM

## ActionFSM（动作覆盖层）
## 状态：None / Attack / AttackCancel / Hurt / Die
## 攻击分为左右手（side: R/L）存储在单独变量
## 全局：Die(pr=100) > Hurt(pr=90)
## GREEN：Attack/Cancel → Walk/Run (pr=50/51) 允许动作中移动
## 动作结束统一走 resolve_post_action_state
## 禁止：播放动画、改 velocity

enum State { NONE, ATTACK, ATTACK_CANCEL, FUSE, HURT, DIE }

const STATE_NAMES: Array[StringName] = [
	&"None", &"Attack", &"AttackCancel", &"Fuse", &"Hurt", &"Die"
]

const DEFAULT_HURT_TIMEOUT: float = 1.0  ## Hurt 默认超时（stun 结束后恢复此值）

var state: int = State.NONE
var attack_side: String = ""  # "R" / "L" / "" - 当前攻击使用的手（仅Attack/AttackCancel时有效）
var _player: Player = null
var _weapon_controller: WeaponController = null

## PLANNED: 未来蓄力类武器可能需要"移动打断攻击"功能
var allow_move_interrupt_action: bool = false

## S3: 卡死保护 - 超时强制 resolver
var _attack_timeout: float = 2.0  # 2秒超时
var _attack_timer: float = 0.0    # 当前计时器
var _hurt_timeout: float = DEFAULT_HURT_TIMEOUT
var _hurt_timer: float = 0.0
var _fuse_timer: float = 0.0
var _return_idle_after_hurt: bool = false
var _use_fuse_hurt_anim: bool = false


func state_name() -> StringName:
	var base_name: StringName = STATE_NAMES[state] if state >= 0 and state < STATE_NAMES.size() else &"?"
	# Attack/AttackCancel 加上 side 后缀以便日志清晰
	if state == State.ATTACK and attack_side != "":
		return StringName(String(base_name) + "_" + attack_side)
	elif state == State.ATTACK_CANCEL and attack_side != "":
		return StringName(String(base_name) + "_" + attack_side)
	return base_name


func setup(player: Player) -> void:
	_player = player
	_weapon_controller = player.weapon_controller if player != null else null
	state = State.NONE



func tick(_dt: float) -> void:
	if _player == null:
		return

	# === CRITICAL FIX: DIE 最高优先级检查 ===
	if state == State.DIE:
		_attack_timer = 0.0
		_fuse_timer = 0.0
		return  # 终态：不执行任何逻辑

	# === GLOBAL pr=100: hp<=0 → Die ===
	var hp: int = _player.health.hp if _player.health != null else 1
	if hp <= 0 and state != State.DIE:
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
			_hurt_timeout = DEFAULT_HURT_TIMEOUT  # B1修复：恢复默认超时
			_resolve_and_transition("hurt_timeout_protection")
			return
	else:
		_hurt_timer = 0.0


	# === Fuse 超时保护（纯安全兜底，正常由动画完成事件退出）===
	if state == State.FUSE:
		_fuse_timer += _dt
		# 宽松超时：给动画充足播放时间，仅作为真正卡死时的保险
		var fuse_timeout: float = 3.0
		if _player != null:
			fuse_timeout = maxf(fuse_timeout, _player.fusion_lock_time + 2.0)
		if _fuse_timer > fuse_timeout:
			if _player != null and _player.has_method("log_msg"):
				_player.log_msg("ACTION", "WARNING: Fuse timeout after %.2fs — animation completion may have been lost" % _fuse_timer)
			on_anim_end_fuse()
			return
	else:
		_fuse_timer = 0.0


# ── 外部事件入口 ──

## 强制释放槽位（用于 cancel 动画结束时确保 slot 不卡死）
func _force_release_slot(side: String) -> void:
	if _player == null or _player.chain_sys == null:
		return

	if _player.chain_sys.has_method("release"):
		_player.chain_sys.release(side)
	else:
		# 契约违反：ChainSystem 缺少 release 方法
		push_warning("[ActionFSM] ChainSystem missing release() method — slot '%s' may leak" % side)

	if _player.has_method("log_msg"):
		_player.log_msg("ACTION", "force_release_slot(%s)" % side)


func on_damaged() -> void:
	if _player == null:
		return
	if state == State.DIE:
		return

	_log_event("damaged")

	var hp: int = _player.health.hp if _player.health != null else 1

	# === hp<=0 → Die（清理逻辑已在_do_transition中统一处理）===
	if hp <= 0:
		_do_transition(State.DIE, "damaged->DIE(hp<=0)", 100)
		return

	# === hp>0 的情况：受伤 ===
	if state == State.FUSE:
		if _player.chain_sys != null and _player.chain_sys.has_method("abort_fuse_cast"):
			_player.chain_sys.abort_fuse_cast()
		_return_idle_after_hurt = true
		_use_fuse_hurt_anim = true
	elif _player.chain_sys != null and _player.chain_sys.has_method("cancel_volatile_on_damage"):
		# 非融合受击：取消 FLYING/STUCK，但保留 LINKED
		_player.chain_sys.cancel_volatile_on_damage()

	# 如果正在动作中，中断动作（但槽位已由上面的 cancel_volatile_on_damage 处理）
	if state in [State.ATTACK, State.ATTACK_CANCEL]:
		attack_side = ""  # 清空 side 标记

	_do_transition(State.HURT, "damaged->HURT", 90)



## on_stunned(seconds): 外部僵直（不扣血，只冻结输入/动作）
func on_stunned(seconds: float) -> void:
	if _player == null:
		return
	if state == State.DIE:
		return
	_hurt_timeout = seconds  # 临时覆盖 hurt 超时为僵直时长
	_do_transition(State.HURT, "stunned(%.2fs)" % seconds, 90)


func on_space_pressed() -> void:
	if _player == null:
		return
	if state == State.DIE or state == State.HURT:
		return
	if _player.chain_sys == null:
		return
	if not _player.chain_sys.has_method("begin_fuse_cast"):
		return
	var ok: bool = bool(_player.chain_sys.begin_fuse_cast())
	if not ok:
		return
	attack_side = ""
	_do_transition(State.FUSE, "space->FUSE", 95)


func on_anim_end_fuse() -> void:
	if state != State.FUSE:
		return
	if _player != null and _player.chain_sys != null and _player.chain_sys.has_method("commit_fuse_cast"):
		_player.chain_sys.commit_fuse_cast()
	_resolve_and_transition("anim_end_fuse")


func should_use_fuse_hurt_anim() -> bool:
	return _use_fuse_hurt_anim


func on_m_pressed() -> void:
	## Chain 武器走 player.gd 直通路径（绕过 ActionFSM），此方法仅处理 Sword/Knife
	if _player == null:
		return
	if state == State.DIE or state == State.HURT:
		return
	if state != State.NONE:
		return  # 已在动作中，忽略

	_log_event("M_pressed")

	if _weapon_controller == null:
		if _player.has_method("log_msg"):
			_player.log_msg("ACTION", "M_pressed FAILED: no weapon_controller")
		return

	# Chain 武器不走 ActionFSM（由 player.gd → ChainSystem 直接处理）
	if _weapon_controller.current_weapon == _weapon_controller.WeaponType.CHAIN:
		return

	# Sword / Knife: 进入 ATTACK 状态
	attack_side = "R"
	var weapon_name: String = _weapon_controller.get_weapon_name()
	_do_transition(State.ATTACK, "M_pressed weapon=%s" % weapon_name, 5)


func on_x_pressed() -> void:
	if _player == null:
		return
	if state == State.DIE or state == State.HURT:
		return

	_log_event("X_pressed")

	# PINK pr=6: Attack → AttackCancel
	if state == State.ATTACK:
		_do_transition(State.ATTACK_CANCEL, "X_pressed", 6)
		# 保护：只在 slot 被占用时才 cancel（避免重复 cancel）
		if attack_side == "R" and _player.chain_sys != null and not _player.chain_sys.slot_R_available:
			_player.chain_sys.cancel("R")
		elif attack_side == "L" and _player.chain_sys != null and not _player.chain_sys.slot_L_available:
			_player.chain_sys.cancel("L")

	# None状态：检查是否有链条绑定，如果有则取消所有链条
	elif state == State.NONE:
		if _weapon_controller != null and _weapon_controller.current_weapon == _weapon_controller.WeaponType.CHAIN:
			if _player.chain_sys != null and _player.chain_sys.has_method("force_dissolve_all_chains"):
				_player.chain_sys.force_dissolve_all_chains()
				if _player.has_method("log_msg"):
					_player.log_msg("ACTION", "X_pressed in None: dissolved all chains")


func on_weapon_switched() -> void:
	"""武器切换（Z键）：硬切，中断当前动作"""
	if _player == null:
		return
	if state == State.DIE:
		return  # 死亡时不允许切换

	_log_event("weapon_switched")

	# === CRITICAL FIX: 切换武器时dissolve所有链（包括LINKED）===
	# 这符合 Q3:选项A，相当于自动按X
	if _player.chain_sys != null and _player.chain_sys.has_method("force_dissolve_all_chains"):
		_player.chain_sys.force_dissolve_all_chains()
		if _player.has_method("log_msg"):
			_player.log_msg("ACTION", "weapon_switched: dissolved all chains")

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
		_hurt_timeout = DEFAULT_HURT_TIMEOUT  # B1修复：恢复默认超时
		if _return_idle_after_hurt:
			_return_idle_after_hurt = false
			_use_fuse_hurt_anim = false
			_do_transition(State.NONE, "anim_end_hurt->idle_after_fuse_interrupt", 90)
			_sync_loco(&"Idle", "GREEN")
			return
		_use_fuse_hurt_anim = false
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
		_sync_loco(resolved, "resolver")


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


## R3合并：统一的 LocomotionFSM 同步方法
func _sync_loco(target_state_name: StringName, source: String) -> void:
	var loco: PlayerLocomotionFSM = _player.loco_fsm
	if loco == null:
		return

	var target_state: int = -1
	match target_state_name:
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
			_player.log_msg("ACTION", "SYNC_LOCO %s->%s (%s)" % [from_name, to_name, source])


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
		# 1. 死亡：立即清空所有链条（不走溶解，不依赖 tick/tween）
		if _player.chain_sys != null:
			if _player.chain_sys.has_method("hard_clear_all_chains"):
				_player.chain_sys.hard_clear_all_chains("die")
			else:
				_player.chain_sys.force_dissolve_all_chains()

		# 2. 冻结movement（虽然movement自己也会检查Die，但这里主动冻结更保险）
		if _player.movement != null:
			_player.movement.move_intent = 0  # MoveIntent.NONE
			_player.movement.input_dir = 0.0
			_player.velocity.x = 0.0
			if _player.velocity.y < 0.0:
				_player.velocity.y = 0.0

		# 3. 停止受击/击退等健康侧效果，确保死亡后完全静止可控
		if _player.health != null and _player.health.has_method("on_player_die"):
			_player.health.on_player_die()

		# 4. 通知Player执行死亡入口级别清理（兜底清链、清pending输入）
		if _player.has_method("on_die_entered"):
			_player.on_die_entered()

	if _player != null and _player.has_method("log_msg"):
		_player.log_msg("ACTION",
			"TRANS=%s->%s reason=%s pr=%d" % [from_name, to_name, reason, priority])


# ── 日志 ──

func _log_event(event: String) -> void:
	if _player != null and _player.has_method("log_msg"):
		_player.log_msg("ACTION", "EVENT=%s" % event)
