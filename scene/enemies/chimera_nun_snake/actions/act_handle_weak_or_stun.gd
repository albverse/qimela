extends ActionLeaf
class_name ActNunSnakeHandleWeakOrStun

## =============================================================================
## WEAK / STUN 状态处理
## =============================================================================
## 入场动画规则：
## - eye_phase == SOCKETED → weak / stun 动画 → weak_loop / stun_loop
## - eye_phase != SOCKETED → shoot_eye_recall_weak_or_stun → weak_loop / stun_loop
## 状态期间可被 chain 链接，结束后链接解除。
## =============================================================================

var _entered_loop: bool = false


func before_run(actor: Node, _blackboard: Blackboard) -> void:
	_entered_loop = false
	# 入场动画已在 _enter_weak / _enter_stun 中播放


func tick(actor: Node, _blackboard: Blackboard) -> int:
	var snake: ChimeraNunSnake = actor as ChimeraNunSnake
	if snake == null:
		return FAILURE

	# 不再是 WEAK/STUN → 退出
	if snake.mode != ChimeraNunSnake.Mode.WEAK and snake.mode != ChimeraNunSnake.Mode.STUN:
		return SUCCESS

	# 等待入场动画完成
	if not _entered_loop:
		var is_weak: bool = snake.mode == ChimeraNunSnake.Mode.WEAK
		if snake.eye_phase != ChimeraNunSnake.EyePhase.SOCKETED:
			# 等待 shoot_eye_recall_weak_or_stun 完成
			if snake.anim_is_finished(&"shoot_eye_recall_weak_or_stun"):
				_entered_loop = true
				var loop_anim: StringName = &"weak_loop" if is_weak else &"stun_loop"
				snake.anim_play(loop_anim, true)
			return RUNNING
		else:
			var enter_anim: StringName = &"weak" if is_weak else &"stun"
			if snake.anim_is_finished(enter_anim):
				_entered_loop = true
				var loop_anim: StringName = &"weak_loop" if is_weak else &"stun_loop"
				snake.anim_play(loop_anim, true)
			return RUNNING

	# 循环中，等待时间到
	snake.velocity.x = 0.0
	return RUNNING


func interrupt(actor: Node, blackboard: Blackboard) -> void:
	_entered_loop = false
	super(actor, blackboard)
