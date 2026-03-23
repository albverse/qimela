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
var _phase_elapsed: float = 0.0
var _landing_start_y: float = 0.0
var _logged_stuck_fall_loop: bool = false


func before_run(actor: Node, _blackboard: Blackboard) -> void:
	var sd: SoulDevourer = actor as SoulDevourer
	if sd == null:
		return
	_phase = Phase.FALL_LOOP
	_phase_elapsed = 0.0
	_landing_start_y = sd.global_position.y
	_logged_stuck_fall_loop = false
	sd._idle_elapsed = 0.0
	sd._is_wandering = false
	sd.velocity = Vector2.ZERO
	if _is_grounded_for_landing(sd):
		_phase = Phase.FALL_DOWN
		sd.anim_play(&"normal/fall_down", false)
	else:
		sd.anim_play(&"normal/fall_loop", true)


func tick(actor: Node, _blackboard: Blackboard) -> int:
	var sd: SoulDevourer = actor as SoulDevourer
	if sd == null:
		return FAILURE

	var dt: float = get_physics_process_delta_time()
	_phase_elapsed += dt

	match _phase:
		Phase.FALL_LOOP:
			sd.velocity.x = 0.0
			sd.velocity.y = maxf(sd.velocity.y, 0.0) + sd.fall_speed * dt
			sd.move_and_slide()
			if _is_grounded_for_landing(sd):
				_phase = Phase.FALL_DOWN
				_phase_elapsed = 0.0
				sd.velocity = Vector2.ZERO
				sd.anim_play(&"normal/fall_down", false)
			elif _phase_elapsed >= 0.75 and not _logged_stuck_fall_loop:
				_logged_stuck_fall_loop = true
				print("[SD:P1] landing fall_loop linger: pos=%s start_y=%.1f vel=%s mask=%d ray=%s floor=%s" % [
					sd.global_position, _landing_start_y, sd.velocity, sd.collision_mask,
					_is_raycast_grounded(sd), sd.is_on_floor()])
		Phase.FALL_DOWN:
			sd.velocity = Vector2.ZERO
			if sd.anim_is_finished(&"normal/fall_down"):
				_phase = Phase.DONE
		Phase.DONE:
			sd.velocity = Vector2.ZERO
			sd._on_landing_complete()
			return SUCCESS

	return RUNNING


func interrupt(actor: Node, blackboard: Blackboard) -> void:
	var sd: SoulDevourer = actor as SoulDevourer
	if sd != null:
		sd.velocity = Vector2.ZERO
	super(actor, blackboard)


func _is_grounded_for_landing(sd: SoulDevourer) -> bool:
	return sd.is_on_floor() or _is_raycast_grounded(sd)


func _is_raycast_grounded(sd: SoulDevourer) -> bool:
	var ground_raycast: RayCast2D = sd.get_node_or_null("GroundRaycast") as RayCast2D
	if ground_raycast == null:
		return false
	ground_raycast.force_raycast_update()
	return ground_raycast.is_colliding()
