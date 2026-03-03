extends ActionLeaf
class_name ActGhostHandLinkedMove

## 幽灵手跟随：被链接时随玩家移动（无重力，飞行）。
## 永远返回 RUNNING。

const FOLLOW_OFFSET: Vector2 = Vector2(-80.0, -40.0)
## 跟随偏移：幽灵手悬停在玩家左上方


func tick(actor: Node, _blackboard: Blackboard) -> int:
	var ghost := actor as ChimeraGhostHandL
	if ghost == null:
		return FAILURE

	var player := ghost.get_player_node()
	if player == null:
		ghost.velocity = Vector2.ZERO
		ghost.move_and_slide()
		if not ghost.anim_is_playing(&"idle_float"):
			ghost.anim_play(&"idle_float", true, true)
		return RUNNING

	var target := player.global_position + FOLLOW_OFFSET
	var to_target := target - ghost.global_position
	var dist := to_target.length()

	if dist > 8.0:
		ghost.velocity = to_target.normalized() * ghost.float_speed
		if not ghost.anim_is_playing(&"move_float") and not ghost.anim_is_playing(&"idle_float"):
			ghost.anim_play(&"move_float", true, true)
	else:
		ghost.velocity = Vector2.ZERO
		if not ghost.anim_is_playing(&"idle_float"):
			ghost.anim_play(&"idle_float", true, true)

	ghost.move_and_slide()
	return RUNNING


func interrupt(actor: Node, blackboard: Blackboard) -> void:
	var ghost := actor as ChimeraGhostHandL
	if ghost != null:
		ghost.velocity = Vector2.ZERO
	super(actor, blackboard)
