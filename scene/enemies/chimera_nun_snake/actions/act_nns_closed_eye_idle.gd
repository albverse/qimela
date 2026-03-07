extends ActionLeaf
class_name ActNNSClosedEyeIdle

## 闭眼兜底行为：
##   感知目标后选择意图（开眼攻击 or 闭眼攻击 or 移动接敌）。
##   若无目标：closed_eye_idle 原地待机。
## 永远返回 RUNNING（兜底分支，由高优先级分支打断）。

const COOLDOWN_KEY_GROUND_POUND: StringName = &"cooldown_nns_ground_pound"
const COOLDOWN_KEY_OPEN_EYE: StringName = &"cooldown_nns_open_eye"

@export var ground_pound_cooldown: float = 4.0
@export var open_eye_cooldown: float = 3.0

enum SubPhase {
	IDLE,         ## 原地待机（无目标）
	MOVE_TO,      ## 移动接敌（闭眼走）
	GROUND_POUND, ## 执行锤地
	WAKING,       ## 播放 close_to_open，完成后切 OPEN_EYE
}

var _sub_phase: int = SubPhase.IDLE


func before_run(actor: Node, _blackboard: Blackboard) -> void:
	_sub_phase = SubPhase.IDLE


func tick(actor: Node, blackboard: Blackboard) -> int:
	var nns := actor as ChimeraNunSnake
	if nns == null:
		return FAILURE

	var dt := nns.get_physics_process_delta_time()
	nns.velocity.y += 800.0 * dt

	match _sub_phase:
		SubPhase.IDLE:
			_tick_idle(nns, blackboard)
		SubPhase.MOVE_TO:
			_tick_move_to(nns, blackboard)
		SubPhase.GROUND_POUND:
			_tick_ground_pound(nns, blackboard)
		SubPhase.WAKING:
			_tick_waking(nns)

	nns.move_and_slide()
	return RUNNING


func _tick_idle(nns: ChimeraNunSnake, blackboard: Blackboard) -> void:
	nns.velocity.x = 0.0
	if not nns.anim_is_playing(&"closed_eye_idle"):
		nns.anim_play(&"closed_eye_idle", true)

	var target: Node2D = nns.get_player()
	if target == null:
		return

	blackboard.set_value("target_node", target)

	# 更新朝向
	var dir_x: float = signf(target.global_position.x - nns.global_position.x)
	if dir_x != 0.0:
		nns.facing = int(dir_x)

	_select_intent(nns, blackboard, target)


func _select_intent(nns: ChimeraNunSnake, blackboard: Blackboard, _target: Node2D) -> void:
	var actor_id := str(nns.get_instance_id())
	var now_ms: int = ChimeraNunSnake.now_ms()

	# 优先：锤地（在范围内且冷却结束）
	var gp_cd_end: float = blackboard.get_value(COOLDOWN_KEY_GROUND_POUND, 0.0, actor_id)
	if nns.is_player_in_range(nns.ground_pound_range) and now_ms >= int(gp_cd_end):
		_sub_phase = SubPhase.GROUND_POUND
		nns.anim_play(&"ground_pound", false)
		return

	# 次选：开眼（冷却结束）
	var oe_cd_end: float = blackboard.get_value(COOLDOWN_KEY_OPEN_EYE, 0.0, actor_id)
	if now_ms >= int(oe_cd_end):
		_sub_phase = SubPhase.WAKING
		nns.opening_transition_lock = true
		nns.anim_play(&"close_to_open", false)
		return

	# 否则移动接敌
	_sub_phase = SubPhase.MOVE_TO


func _tick_move_to(nns: ChimeraNunSnake, blackboard: Blackboard) -> void:
	var target: Node2D = blackboard.get_value("target_node") as Node2D
	if target == null or not is_instance_valid(target):
		_sub_phase = SubPhase.IDLE
		return

	nns.anim_play(&"closed_eye_walk", true)

	# 更新朝向
	var dir: float = signf(target.global_position.x - nns.global_position.x)
	if dir != 0.0:
		nns.facing = int(dir)

	var h_dist: float = absf(target.global_position.x - nns.global_position.x)
	if h_dist <= nns.stiff_attack_range:
		_sub_phase = SubPhase.IDLE
		return

	nns.velocity.x = dir * nns.closed_walk_speed
	if nns.is_on_wall():
		nns.velocity.x = 0.0


func _tick_ground_pound(nns: ChimeraNunSnake, blackboard: Blackboard) -> void:
	nns.velocity.x = 0.0

	if nns.ev_atk_hit_on:
		nns.ev_atk_hit_on = false
		nns.atk_hit_window_open = true
		if nns._ground_pound_hitbox != null:
			nns._ground_pound_hitbox.monitoring = true
	if nns.ev_atk_hit_off:
		nns.ev_atk_hit_off = false
		nns.atk_hit_window_open = false
		if nns._ground_pound_hitbox != null:
			nns._ground_pound_hitbox.monitoring = false

	if nns.anim_is_finished(&"ground_pound"):
		nns.atk_hit_window_open = false
		if nns._ground_pound_hitbox != null:
			nns._ground_pound_hitbox.monitoring = false
		var actor_id := str(nns.get_instance_id())
		blackboard.set_value(COOLDOWN_KEY_GROUND_POUND,
			float(ChimeraNunSnake.now_ms()) + ground_pound_cooldown * 1000.0, actor_id)
		_sub_phase = SubPhase.IDLE


func _tick_waking(nns: ChimeraNunSnake) -> void:
	nns.velocity.x = 0.0
	## close_to_open 播放中（此阶段 EyeHurtbox 由 Spine 事件 eye_hurtbox_enable 开启）
	## 完成后切入 OPEN_EYE，让 SelectorReactive 下帧走 Seq_OpenEyeAttack 分支
	if nns.ev_close_to_open_done or nns.anim_is_finished(&"close_to_open"):
		nns.ev_close_to_open_done = false
		nns.opening_transition_lock = false
		nns.enter_mode(ChimeraNunSnake.Mode.OPEN_EYE)
		_sub_phase = SubPhase.IDLE


func interrupt(actor: Node, blackboard: Blackboard) -> void:
	var nns := actor as ChimeraNunSnake
	if nns != null:
		nns.velocity = Vector2.ZERO
		nns.force_close_hit_windows()
		nns.opening_transition_lock = false
		nns.closing_transition_lock = false
		if nns._ground_pound_hitbox != null:
			nns._ground_pound_hitbox.monitoring = false
	_sub_phase = SubPhase.IDLE
	super(actor, blackboard)
