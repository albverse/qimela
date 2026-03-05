extends ActionLeaf
class_name ActMolluscWeakStun

## 软体虫虚弱眩晕：先播 weak_stun（一次）再进入 weak_stun_loop（循环），始终 RUNNING。
## 由 CondMolluscWeak 守卫；虚弱恢复后 SelectorReactive 自动中断。

enum Phase {
	ENTER,
	LOOP,
}

var _phase: int = Phase.ENTER


func before_run(actor: Node, _blackboard: Blackboard) -> void:
	var mollusc := actor as Mollusc
	if mollusc == null:
		return
	_phase = Phase.ENTER
	mollusc.velocity = Vector2.ZERO
	mollusc.anim_play(&"weak_stun", false, false)

func tick(actor: Node, _blackboard: Blackboard) -> int:
	var mollusc := actor as Mollusc
	if mollusc == null:
		return FAILURE
	mollusc.velocity = Vector2.ZERO

	if _phase == Phase.ENTER:
		if mollusc.anim_is_finished(&"weak_stun"):
			_phase = Phase.LOOP
			mollusc.anim_play(&"weak_stun_loop", true, false)
		elif not mollusc.anim_is_playing(&"weak_stun"):
			# 防止被其他动作/受击打断后丢失入场动画。
			mollusc.anim_play(&"weak_stun", false, false)
	else:
		if not mollusc.anim_is_playing(&"weak_stun_loop"):
			mollusc.anim_play(&"weak_stun_loop", true, false)
	return RUNNING


func interrupt(actor: Node, blackboard: Blackboard) -> void:
	var mollusc := actor as Mollusc
	if mollusc != null:
		mollusc.velocity = Vector2.ZERO
	_phase = Phase.ENTER
	super(actor, blackboard)
