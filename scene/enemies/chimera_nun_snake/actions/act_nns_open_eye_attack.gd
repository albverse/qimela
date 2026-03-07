extends ActionLeaf
class_name ActNNSOpenEyeAttack

## 睁眼系攻击流（OPEN_EYE）—— 固定攻击链，不是自由待机态。
## 进入本节点时，close_to_open 已完成，mode==OPEN_EYE。
## 固定链路：stiff_attack → open_eye_idle → shoot_eye_start → shoot_eye_loop → shoot_eye_end → 关眼
## 期间禁止水平移动，重力正常施加（防浮空）。

const COOLDOWN_KEY_STIFF: StringName = &"cooldown_nns_stiff"
const COOLDOWN_KEY_SHOOT: StringName = &"cooldown_nns_shoot"

enum Phase {
	STIFF_ATTACK,      ## 僵直攻击（直接开始，无前置 idle）
	OPEN_IDLE_POST,    ## stiff_attack 结束后的短暂停留，然后进入 shoot_eye
	SHOOT_EYE_START,   ## 发射眼球起手
	SHOOT_EYE_LOOP,    ## 眼球在外，本体维持无眼睁眼
	SHOOT_EYE_ENDING,  ## 眼球返航 / 强制召回结束动画
	CLOSING,           ## open_eye_to_close 关眼
}

@export var stiff_attack_cooldown: float = 3.0
@export var shoot_eye_cooldown: float = 5.0

var _phase: int = Phase.STIFF_ATTACK
var _open_idle_start_ms: int = 0


func before_run(actor: Node, blackboard: Blackboard) -> void:
	## before_run 被 SelectorReactive 每帧调用（对非 running_child）。
	## 此时 mode 已是 OPEN_EYE，直接启动 stiff_attack。
	var nns := actor as ChimeraNunSnake
	if nns == null:
		return
	_phase = Phase.STIFF_ATTACK
	nns.anim_play(&"stiff_attack", false)


func tick(actor: Node, blackboard: Blackboard) -> int:
	var nns := actor as ChimeraNunSnake
	if nns == null:
		return FAILURE

	# WEAK / STUN 强制退出
	if nns.mode == ChimeraNunSnake.Mode.WEAK or nns.mode == ChimeraNunSnake.Mode.STUN:
		return SUCCESS

	var dt := nns.get_physics_process_delta_time()
	nns.velocity.x = 0.0
	nns.velocity.y += 800.0 * dt
	nns.move_and_slide()

	match _phase:
		Phase.STIFF_ATTACK:
			return _tick_stiff_attack(nns, blackboard)
		Phase.OPEN_IDLE_POST:
			return _tick_open_idle_post(nns, blackboard)
		Phase.SHOOT_EYE_START:
			return _tick_shoot_eye_start(nns, blackboard)
		Phase.SHOOT_EYE_LOOP:
			return _tick_shoot_eye_loop(nns)
		Phase.SHOOT_EYE_ENDING:
			return _tick_shoot_eye_ending(nns)
		Phase.CLOSING:
			return _tick_closing(nns)

	return RUNNING


func _tick_stiff_attack(nns: ChimeraNunSnake, blackboard: Blackboard) -> int:
	if nns.ev_atk_hit_on:
		nns.ev_atk_hit_on = false
		nns.atk_hit_window_open = true
	if nns.ev_atk_hit_off:
		nns.ev_atk_hit_off = false
		nns.atk_hit_window_open = false

	if nns.anim_is_finished(&"stiff_attack"):
		nns.atk_hit_window_open = false
		var actor_id := str(nns.get_instance_id())
		blackboard.set_value(COOLDOWN_KEY_STIFF,
			float(ChimeraNunSnake.now_ms()) + stiff_attack_cooldown * 1000.0, actor_id)
		_phase = Phase.OPEN_IDLE_POST
		_open_idle_start_ms = ChimeraNunSnake.now_ms()
		nns.anim_play(&"open_eye_idle", true)

	return RUNNING


func _tick_open_idle_post(nns: ChimeraNunSnake, blackboard: Blackboard) -> int:
	var elapsed_ms: int = ChimeraNunSnake.now_ms() - _open_idle_start_ms
	if elapsed_ms < int(nns.open_eye_idle_timeout * 1000.0):
		return RUNNING

	var actor_id := str(nns.get_instance_id())
	var shoot_cd_end: float = blackboard.get_value(COOLDOWN_KEY_SHOOT, 0.0, actor_id)
	var can_shoot: bool = (
		nns.eye_phase == ChimeraNunSnake.EyePhase.SOCKETED
		and ChimeraNunSnake.now_ms() >= int(shoot_cd_end)
	)

	if can_shoot:
		_phase = Phase.SHOOT_EYE_START
		nns.anim_play(&"shoot_eye_start", false)
		return RUNNING

	_start_closing(nns)
	return RUNNING


func _tick_shoot_eye_start(nns: ChimeraNunSnake, blackboard: Blackboard) -> int:
	if nns.ev_eye_shoot_spawn:
		nns.ev_eye_shoot_spawn = false
		nns.spawn_eye_projectile()

	if nns.anim_is_finished(&"shoot_eye_start"):
		_phase = Phase.SHOOT_EYE_LOOP
		nns.anim_play(&"shoot_eye_loop", true)
		var actor_id := str(nns.get_instance_id())
		blackboard.set_value(COOLDOWN_KEY_SHOOT,
			float(ChimeraNunSnake.now_ms()) + shoot_eye_cooldown * 1000.0, actor_id)

	return RUNNING


func _tick_shoot_eye_loop(nns: ChimeraNunSnake) -> int:
	match nns.eye_phase:
		ChimeraNunSnake.EyePhase.SOCKETED:
			_phase = Phase.SHOOT_EYE_ENDING
			nns.anim_play(&"shoot_eye_end", false)
		ChimeraNunSnake.EyePhase.FORCE_RECALL:
			_phase = Phase.SHOOT_EYE_ENDING
			nns.anim_play(&"shoot_eye_recall_weak_or_stun", false)
	return RUNNING


func _tick_shoot_eye_ending(nns: ChimeraNunSnake) -> int:
	if nns.anim_is_finished(&"shoot_eye_end") or nns.anim_is_finished(&"shoot_eye_recall_weak_or_stun"):
		_start_closing(nns)
	return RUNNING


func _start_closing(nns: ChimeraNunSnake) -> void:
	_phase = Phase.CLOSING
	nns.closing_transition_lock = true
	nns.anim_play(&"open_eye_to_close", false)


func _tick_closing(nns: ChimeraNunSnake) -> int:
	if nns.ev_open_to_close_done or nns.anim_is_finished(&"open_eye_to_close"):
		nns.ev_open_to_close_done = false
		nns.closing_transition_lock = false
		nns.enter_mode(ChimeraNunSnake.Mode.CLOSED_EYE)
		return SUCCESS
	return RUNNING


func interrupt(actor: Node, blackboard: Blackboard) -> void:
	var nns := actor as ChimeraNunSnake
	if nns != null:
		nns.velocity = Vector2.ZERO
		nns.force_close_hit_windows()
		nns.opening_transition_lock = false
		nns.closing_transition_lock = false
		if nns.eye_phase != ChimeraNunSnake.EyePhase.SOCKETED:
			nns.eye_phase = ChimeraNunSnake.EyePhase.FORCE_RECALL
	super(actor, blackboard)
