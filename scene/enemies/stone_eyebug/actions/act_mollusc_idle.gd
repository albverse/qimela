extends ActionLeaf
class_name ActMolluscIdle

## 软体虫待机：玩家远离、无壳可回、不需移动时播 idle 循环，始终 RUNNING。
## 由 SelectorReactive 兜底（所有高优先级分支均 FAILURE 时触发）。

func tick(actor: Node, _blackboard: Blackboard) -> int:
	var mollusc := actor as Mollusc
	if mollusc == null:
		return FAILURE
	mollusc.velocity = Vector2.ZERO
	if not mollusc.anim_is_playing(&"idle"):
		mollusc.anim_play(&"idle", true, true)
	return RUNNING


func interrupt(actor: Node, blackboard: Blackboard) -> void:
	var mollusc := actor as Mollusc
	if mollusc != null:
		mollusc.velocity = Vector2.ZERO
	super(actor, blackboard)
