extends ActionLeaf
class_name ActWGWaitDeath

## 等待死亡/被吞食动画完毕 → queue_free()（由信号回调处理）。

func tick(actor: Node, _blackboard: Blackboard) -> int:
	var ghost: WanderingGhost = actor as WanderingGhost
	if ghost == null:
		return FAILURE
	ghost.velocity = Vector2.ZERO
	return RUNNING


func interrupt(actor: Node, blackboard: Blackboard) -> void:
	super(actor, blackboard)
