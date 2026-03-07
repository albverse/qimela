extends ActionLeaf
class_name ActNNSWeakStunHandle

## 处理 WEAK / STUN 状态：播放对应动画，等待状态自然结束。
## 入场动画规则（v0.7 蓝图 §5.4）：
##   - eye_phase == SOCKETED → 有眼状态：播放 weak / stun 进入动画，然后 loop
##   - eye_phase != SOCKETED → 无眼状态：统一播放 shoot_eye_recall_weak_or_stun，
##     结束后直接进入 weak_loop / stun_loop
## 期间禁止移动，重力正常施加。
## 状态由 chimera_nun_snake._physics_process 中的倒计时自然结束，
## 本节点持续返回 RUNNING，直到 mode 不再是 WEAK/STUN。

enum EntryAnim {
	NONE,             ## 尚未确定
	SOCKETED_ENTER,   ## 有眼进入（weak / stun）
	RECALL_ENTER,     ## 无眼进入（shoot_eye_recall_weak_or_stun）
}

var _entry_anim: int = EntryAnim.NONE
var _recall_done: bool = false


func before_run(actor: Node, _blackboard: Blackboard) -> void:
	_entry_anim = EntryAnim.NONE
	_recall_done = false


func tick(actor: Node, _blackboard: Blackboard) -> int:
	var nns := actor as ChimeraNunSnake
	if nns == null:
		return FAILURE

	# 状态已结束，退出
	if nns.mode != ChimeraNunSnake.Mode.WEAK and nns.mode != ChimeraNunSnake.Mode.STUN:
		return SUCCESS

	var dt := nns.get_physics_process_delta_time()
	nns.velocity.x = 0.0
	nns.velocity.y += 800.0 * dt
	nns.move_and_slide()

	# 首次 tick：确定入场动画路径
	if _entry_anim == EntryAnim.NONE:
		if nns.eye_phase == ChimeraNunSnake.EyePhase.SOCKETED:
			_entry_anim = EntryAnim.SOCKETED_ENTER
			if nns.mode == ChimeraNunSnake.Mode.WEAK:
				nns.anim_play(&"weak", false)
			else:
				nns.anim_play(&"stun", false)
		else:
			# 无眼状态（眼球在外或强制召回中）：统一播放 shoot_eye_recall_weak_or_stun
			_entry_anim = EntryAnim.RECALL_ENTER
			nns.anim_play(&"shoot_eye_recall_weak_or_stun", false)

	match _entry_anim:
		EntryAnim.SOCKETED_ENTER:
			return _tick_socketed(nns)
		EntryAnim.RECALL_ENTER:
			return _tick_recall(nns)

	return RUNNING


func _tick_socketed(nns: ChimeraNunSnake) -> int:
	## 有眼入场：weak/stun 进入动画 → loop
	if nns.mode == ChimeraNunSnake.Mode.WEAK:
		if nns.anim_is_finished(&"weak"):
			nns.anim_play(&"weak_loop", true)
	elif nns.mode == ChimeraNunSnake.Mode.STUN:
		if nns.anim_is_finished(&"stun"):
			nns.anim_play(&"stun_loop", true)
	return RUNNING


func _tick_recall(nns: ChimeraNunSnake) -> int:
	## 无眼入场：shoot_eye_recall_weak_or_stun 结束后直接进入 weak_loop/stun_loop
	if not _recall_done:
		if nns.anim_is_finished(&"shoot_eye_recall_weak_or_stun"):
			_recall_done = true
			# 眼球应在 recall 动画期间返回，phase 已由 _force_eye_recall 切换；
			# 这里再次确认 phase 已 SOCKETED（由 notify_eye_returned 设置）
			if nns.mode == ChimeraNunSnake.Mode.WEAK:
				nns.anim_play(&"weak_loop", true)
			else:
				nns.anim_play(&"stun_loop", true)
	return RUNNING


func interrupt(actor: Node, blackboard: Blackboard) -> void:
	var nns := actor as ChimeraNunSnake
	if nns != null:
		nns.velocity = Vector2.ZERO
	_entry_anim = EntryAnim.NONE
	_recall_done = false
	super(actor, blackboard)
