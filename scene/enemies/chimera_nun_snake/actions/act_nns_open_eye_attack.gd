extends ActionLeaf
class_name ActNNSOpenEyeAttack

## 睁眼系攻击流（OPEN_EYE）：
##   stiff_attack → shoot_eye（若条件满足）→ 关眼
## 常规情况禁止移动。

const COOLDOWN_KEY_STIFF: StringName = &"cooldown_nns_stiff"
const COOLDOWN_KEY_SHOOT: StringName = &"cooldown_nns_shoot"

enum Phase {
	OPEN_ENTERING,    ## 播放 close_to_open（开眼转场）
	OPEN_IDLE,        ## open_eye_idle 待机
	STIFF_ATTACK,     ## 僵直攻击
	SHOOT_EYE_START,  ## 发射眼球起手
	SHOOT_EYE_LOOP,   ## 眼球在外，本体维持无眼睁眼
	SHOOT_EYE_ENDING, ## 眼球返航收尾
	CLOSING,          ## open_eye_to_close 关眼
}

@export var stiff_attack_cooldown: float = 3.0
## 僵直攻击冷却（秒）

@export var shoot_eye_cooldown: float = 5.0
## 发射眼球冷却（秒）

var _phase: int = Phase.OPEN_ENTERING
var _open_idle_start_ms: int = 0


func before_run(actor: Node, blackboard: Blackboard) -> void:
	var nns := actor as ChimeraNunSnake
	if nns == null:
		return
	_phase = Phase.OPEN_ENTERING
	nns.opening_transition_lock = true
	nns.anim_play(&"close_to_open", false)


func tick(actor: Node, blackboard: Blackboard) -> int:
	var nns := actor as ChimeraNunSnake
	if nns == null:
		return FAILURE

	# WEAK / STUN 强制中断
	if nns.mode == ChimeraNunSnake.Mode.WEAK or nns.mode == ChimeraNunSnake.Mode.STUN:
		return SUCCESS

	var dt := nns.get_physics_process_delta_time()
	# 睁眼系禁止水平移动
	nns.velocity.x = 0.0
	nns.velocity.y += 800.0 * dt
	nns.move_and_slide()

	match _phase:
		Phase.OPEN_ENTERING:
			return _tick_entering(nns)
		Phase.OPEN_IDLE:
			return _tick_open_idle(nns, blackboard)
		Phase.STIFF_ATTACK:
			return _tick_stiff_attack(nns, blackboard)
		Phase.SHOOT_EYE_START:
			return _tick_shoot_eye_start(nns, blackboard)
		Phase.SHOOT_EYE_LOOP:
			return _tick_shoot_eye_loop(nns, blackboard)
		Phase.SHOOT_EYE_ENDING:
			return _tick_shoot_eye_ending(nns)
		Phase.CLOSING:
			return _tick_closing(nns)

	return RUNNING


func _tick_entering(nns: ChimeraNunSnake) -> int:
	if nns.ev_close_to_open_done or nns.anim_is_finished(&"close_to_open"):
		nns.ev_close_to_open_done = false
		nns.opening_transition_lock = false
		nns.enter_mode(ChimeraNunSnake.Mode.OPEN_EYE)
		_phase = Phase.OPEN_IDLE
		_open_idle_start_ms = ChimeraNunSnake.now_ms()
		nns.anim_play(&"open_eye_idle", true)
	return RUNNING


func _tick_open_idle(nns: ChimeraNunSnake, blackboard: Blackboard) -> int:
	var elapsed_ms: int = ChimeraNunSnake.now_ms() - _open_idle_start_ms
	if elapsed_ms < int(nns.open_eye_idle_timeout * 1000.0):
		return RUNNING

	var actor_id := str(nns.get_instance_id())
	# 选择攻击：优先 stiff_attack（在范围内且冷却结束）
	var stiff_cd_end: float = blackboard.get_value(COOLDOWN_KEY_STIFF, 0.0, actor_id)
	var can_stiff: bool = (
		nns.is_player_in_range(nns.stiff_attack_range)
		and ChimeraNunSnake.now_ms() >= stiff_cd_end
	)
	if can_stiff:
		_phase = Phase.STIFF_ATTACK
		nns.anim_play(&"stiff_attack", false)
		return RUNNING

	# 否则尝试 shoot_eye
	var shoot_cd_end: float = blackboard.get_value(COOLDOWN_KEY_SHOOT, 0.0, actor_id)
	var can_shoot: bool = (
		nns.eye_phase == ChimeraNunSnake.EyePhase.SOCKETED
		and ChimeraNunSnake.now_ms() >= shoot_cd_end
	)
	if can_shoot:
		_phase = Phase.SHOOT_EYE_START
		nns.anim_play(&"shoot_eye_start", false)
		return RUNNING

	# 没有合适攻击，关眼
	_start_closing(nns)
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
		blackboard.set_value(COOLDOWN_KEY_STIFF, float(ChimeraNunSnake.now_ms()) + stiff_attack_cooldown * 1000.0, actor_id)

		# 攻击结束后可尝试 shoot_eye
		var shoot_cd_end: float = blackboard.get_value(COOLDOWN_KEY_SHOOT, 0.0, actor_id)
		if (
			nns.eye_phase == ChimeraNunSnake.EyePhase.SOCKETED
			and ChimeraNunSnake.now_ms() >= shoot_cd_end
		):
			_phase = Phase.SHOOT_EYE_START
			nns.anim_play(&"shoot_eye_start", false)
		else:
			_start_closing(nns)
	return RUNNING


func _tick_shoot_eye_start(nns: ChimeraNunSnake, blackboard: Blackboard) -> int:
	# 等待 eye_shoot_spawn 事件生成眼球
	if nns.ev_eye_shoot_spawn:
		nns.ev_eye_shoot_spawn = false
		nns.spawn_eye_projectile()

	if nns.anim_is_finished(&"shoot_eye_start"):
		_phase = Phase.SHOOT_EYE_LOOP
		nns.anim_play(&"shoot_eye_loop", true)
		var actor_id := str(nns.get_instance_id())
		blackboard.set_value(COOLDOWN_KEY_SHOOT, float(ChimeraNunSnake.now_ms()) + shoot_eye_cooldown * 1000.0, actor_id)
	return RUNNING


func _tick_shoot_eye_loop(nns: ChimeraNunSnake, _blackboard: Blackboard) -> int:
	# 等待眼球归位（eye_phase 变为 SOCKETED 或 FORCE_RECALL）
	match nns.eye_phase:
		ChimeraNunSnake.EyePhase.SOCKETED:
			# 正常返航完成
			_phase = Phase.SHOOT_EYE_ENDING
			nns.anim_play(&"shoot_eye_end", false)
		ChimeraNunSnake.EyePhase.FORCE_RECALL:
			# 强制召回（进入 WEAK/STUN 触发）
			_phase = Phase.SHOOT_EYE_ENDING
			nns.anim_play(&"shoot_eye_recall", false)
	return RUNNING


func _tick_shoot_eye_ending(nns: ChimeraNunSnake) -> int:
	var finished_end: bool = nns.anim_is_finished(&"shoot_eye_end")
	var finished_recall: bool = nns.anim_is_finished(&"shoot_eye_recall")
	if finished_end or finished_recall:
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
		# 若眼球在外，强制召回
		if nns.eye_phase != ChimeraNunSnake.EyePhase.SOCKETED:
			nns.eye_phase = ChimeraNunSnake.EyePhase.FORCE_RECALL
	super(actor, blackboard)
