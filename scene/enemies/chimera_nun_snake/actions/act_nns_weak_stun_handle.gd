extends ActionLeaf
class_name ActNNSWeakStunHandle

## 处理 WEAK / STUN 状态：播放对应动画，等待状态自然结束。
## 期间禁止移动，禁止转招，眼球若在外则已被强制召回（由 ChimeraNunSnake 在进入状态时处理）。
## 状态结束由 chimera_nun_snake.gd 内的倒计时触发，本节点持续返回 RUNNING。

func tick(actor: Node, _blackboard: Blackboard) -> int:
	var nns := actor as ChimeraNunSnake
	if nns == null:
		return FAILURE

	nns.velocity = Vector2.ZERO
	nns.move_and_slide()

	if nns.mode == ChimeraNunSnake.Mode.WEAK:
		if nns.anim_is_finished(&"weak"):
			nns.anim_play(&"weak_loop", true)
		elif not nns.anim_is_playing(&"weak") and not nns.anim_is_playing(&"weak_loop"):
			nns.anim_play(&"weak", false)
	elif nns.mode == ChimeraNunSnake.Mode.STUN:
		if nns.anim_is_finished(&"stun"):
			nns.anim_play(&"stun_loop", true)
		elif not nns.anim_is_playing(&"stun") and not nns.anim_is_playing(&"stun_loop"):
			nns.anim_play(&"stun", false)
	else:
		# 状态已结束，退出
		return SUCCESS

	return RUNNING


func interrupt(actor: Node, blackboard: Blackboard) -> void:
	var nns := actor as ChimeraNunSnake
	if nns != null:
		nns.velocity = Vector2.ZERO
	super(actor, blackboard)
