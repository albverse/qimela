extends ActionLeaf
class_name ActSoulDevourerLandingSequence

## =============================================================================
## act_landing_sequence — 着陆序列（fall_loop → 地面 → fall_down → 完毕）
## =============================================================================
## P1：_landing_locked = true 时激活，序列完毕调用 _on_landing_complete()。
## =============================================================================

enum Phase {
	FALL_LOOP = 0,
	FALL_DOWN = 1,
	DONE = 2,
}

var _phase: int = Phase.FALL_LOOP


func before_run(actor: Node, _blackboard: Blackboard) -> void:
	_phase = Phase.FALL_LOOP
	var sd: SoulDevourer = actor as SoulDevourer
	if sd == null:
		return
	sd.anim_play(&"normal/fall_loop", true)


func tick(actor: Node, _blackboard: Blackboard) -> int:
	var sd: SoulDevourer = actor as SoulDevourer
	if sd == null:
		return FAILURE

	# 施加重力，向下移动
	var dt: float = get_physics_process_delta_time()
	sd.velocity.y += sd.fall_speed * dt
	sd.move_and_slide()

	match _phase:
		Phase.FALL_LOOP:
			# 检测地面（GroundRaycast 或 is_on_floor）
			var ground_raycast: RayCast2D = sd.get_node_or_null("GroundRaycast") as RayCast2D
			var on_ground: bool = sd.is_on_floor()
			if ground_raycast != null:
				on_ground = ground_raycast.is_colliding()
			if on_ground:
				_phase = Phase.FALL_DOWN
				sd.anim_play(&"normal/fall_down", false)
		Phase.FALL_DOWN:
			if sd.anim_is_finished(&"normal/fall_down"):
				_phase = Phase.DONE
		Phase.DONE:
			sd._on_landing_complete()
			return SUCCESS

	return RUNNING


func interrupt(actor: Node, blackboard: Blackboard) -> void:
	var sd: SoulDevourer = actor as SoulDevourer
	if sd != null:
		sd.velocity.x = 0.0
	super(actor, blackboard)
