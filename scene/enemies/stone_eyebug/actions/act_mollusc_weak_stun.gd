extends ActionLeaf
class_name ActMolluscWeakStun

## 软体虫虚弱眩晕：速度归零，播 weak_stun 循环动画，始终 RUNNING。
## 由 CondMolluscWeak 守卫；虚弱恢复后 SelectorReactive 自动中断。

func tick(actor: Node, _blackboard: Blackboard) -> int:
	var mollusc := actor as Mollusc
	if mollusc == null:
		return FAILURE
	mollusc.velocity = Vector2.ZERO
	if not mollusc.anim_is_playing(&"weak_stun"):
		mollusc.anim_play(&"weak_stun", true, false)
	return RUNNING


func interrupt(actor: Node, blackboard: Blackboard) -> void:
	var mollusc := actor as Mollusc
	if mollusc != null:
		mollusc.velocity = Vector2.ZERO
	super(actor, blackboard)
