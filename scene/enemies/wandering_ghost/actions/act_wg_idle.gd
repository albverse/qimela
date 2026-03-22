extends ActionLeaf
class_name ActWGIdle

## 兜底待机：停止移动，播放 idle，重置追击延迟标志。

func tick(actor: Node, _blackboard: Blackboard) -> int:
	var ghost: WanderingGhost = actor as WanderingGhost
	if ghost == null:
		return FAILURE
	ghost.velocity = Vector2.ZERO
	ghost._play_anim(&"idle", true)
	# 玩家离开检测范围后回到 idle，重置首次追击标志
	ghost._has_started_chase_once = false
	return RUNNING


func interrupt(actor: Node, blackboard: Blackboard) -> void:
	super(actor, blackboard)
