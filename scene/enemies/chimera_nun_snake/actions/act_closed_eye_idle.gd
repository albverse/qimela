extends ActionLeaf
class_name ActNunSnakeClosedEyeIdle

## =============================================================================
## 闭眼待机（兜底行为，永远返回 RUNNING）
## =============================================================================

func before_run(actor: Node, _blackboard: Blackboard) -> void:
	var snake: ChimeraNunSnake = actor as ChimeraNunSnake
	if snake == null:
		return
	if snake.mode == ChimeraNunSnake.Mode.CLOSED_EYE:
		snake.anim_play(&"closed_eye_idle", true)


func tick(actor: Node, _blackboard: Blackboard) -> int:
	var snake: ChimeraNunSnake = actor as ChimeraNunSnake
	if snake == null:
		return FAILURE
	snake.velocity.x = 0.0
	if snake.mode == ChimeraNunSnake.Mode.CLOSED_EYE:
		if not snake.anim_is_playing(&"closed_eye_idle"):
			snake.anim_play(&"closed_eye_idle", true)
	return RUNNING


func interrupt(actor: Node, blackboard: Blackboard) -> void:
	var snake: ChimeraNunSnake = actor as ChimeraNunSnake
	if snake != null:
		snake.velocity.x = 0.0
	super(actor, blackboard)
