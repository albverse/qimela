extends ActionLeaf
class_name ActGhostHandIdleFloat

## 幽灵手 idle：未链接时原地浮动（兜底分支，永远 RUNNING）。


func before_run(actor: Node, _blackboard: Blackboard) -> void:
	var ghost := actor as ChimeraGhostHandL
	if ghost == null:
		return
	ghost.velocity = Vector2.ZERO
	ghost.anim_play(&"idle_float", true, true)


func tick(actor: Node, _blackboard: Blackboard) -> int:
	var ghost := actor as ChimeraGhostHandL
	if ghost == null:
		return FAILURE
	ghost.velocity = Vector2.ZERO
	ghost.move_and_slide()
	return RUNNING


func interrupt(actor: Node, blackboard: Blackboard) -> void:
	var ghost := actor as ChimeraGhostHandL
	if ghost != null:
		ghost.velocity = Vector2.ZERO
	super(actor, blackboard)
