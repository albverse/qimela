extends ActionLeaf
class_name ActSEBStruggleIdle

## 弹翻挣扎等待（兜底）：保持 struggle_loop 动画，速度归零。
## 永远返回 RUNNING；等待 CondSEBAttackedFlipped 触发后由 InnerSelector 切换到 ActSEBEscapeSplit。

func before_run(actor: Node, _blackboard: Blackboard) -> void:
	var seb := actor as StoneEyeBug
	if seb == null:
		return
	seb.velocity = Vector2.ZERO
	if not seb.anim_is_playing(&"struggle_loop"):
		seb.anim_play(&"struggle_loop", true, true)


func tick(actor: Node, _blackboard: Blackboard) -> int:
	var seb := actor as StoneEyeBug
	if seb == null:
		return FAILURE
	seb.velocity = Vector2.ZERO
	if not seb.anim_is_playing(&"struggle_loop"):
		seb.anim_play(&"struggle_loop", true, true)
	return RUNNING


func interrupt(actor: Node, blackboard: Blackboard) -> void:
	var seb := actor as StoneEyeBug
	if seb != null:
		seb.velocity = Vector2.ZERO
	super(actor, blackboard)
