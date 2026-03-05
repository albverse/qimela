extends ActionLeaf
class_name ActGhostHandLinkedMove

## 幽灵手链接操控：被链接时冻结玩家自身移动，将 WASD/Jump 输入重定向到幽灵手。
## A/D → 幽灵手水平移动；W/Jump → 幽灵手上升；S → 幽灵手下降（无重力）。
## 切换 slot 或断开链接时，SelectorReactive interrupt 自动解冻玩家。

const MOVE_SPEED: float = 200.0
## 链接操控速度（px/s）


func before_run(actor: Node, _blackboard: Blackboard) -> void:
	var ghost := actor as ChimeraGhostHandL
	if ghost == null:
		return
	# 冻结玩家自身方向输入
	var player := ghost.get_player_node()
	if player != null and player.has_method("set_external_control_frozen"):
		player.call("set_external_control_frozen", true)


func tick(actor: Node, _blackboard: Blackboard) -> int:
	var ghost := actor as ChimeraGhostHandL
	if ghost == null:
		return FAILURE

	# 将 WASD 输入重定向为幽灵手的速度（无重力，四向自由飞行）
	var dir_x := Input.get_axis(&"move_left", &"move_right")
	var dir_y := Input.get_axis(&"jump", &"move_down")  # W → 上升，S → 下降

	ghost.velocity = Vector2(dir_x, dir_y) * MOVE_SPEED
	ghost.move_and_slide()

	# 动画：有输入播 move_float，静止播 idle_float
	var is_moving := ghost.velocity.length_squared() > 1.0
	if is_moving:
		if not ghost.anim_is_playing(&"move_float"):
			ghost.anim_play(&"move_float", true, true)
	else:
		if not ghost.anim_is_playing(&"idle_float"):
			ghost.anim_play(&"idle_float", true, true)

	return RUNNING


func interrupt(actor: Node, blackboard: Blackboard) -> void:
	var ghost := actor as ChimeraGhostHandL
	if ghost != null:
		# 仅在真正断链时解冻；链接态内（如切到 Attack 分支）保持冻结。
		if not ghost.is_linked():
			var player := ghost.get_player_node()
			if player != null and player.has_method("set_external_control_frozen"):
				player.call("set_external_control_frozen", false)
			ghost.control_input_frozen = false
		ghost.velocity = Vector2.ZERO
	super(actor, blackboard)
