extends ActionLeaf
class_name ActSoulDevourerIdle

## =============================================================================
## act_idle — 兜底待机（P11，永远返回 RUNNING）
## =============================================================================

const WANDER_TRIGGER_DELAY: float = 1.0

func before_run(actor: Node, _blackboard: Blackboard) -> void:
	var sd: SoulDevourer = actor as SoulDevourer
	if sd == null:
		return
	sd._idle_elapsed = 0.0
	sd._is_wandering = false
	sd.velocity.x = 0.0
	sd.anim_play(StringName(sd._get_anim_prefix() + "idle"), true)


func tick(actor: Node, _blackboard: Blackboard) -> int:
	var sd: SoulDevourer = actor as SoulDevourer
	if sd == null:
		return FAILURE

	# 保持 idle 动画
	var idle_anim: StringName = StringName(sd._get_anim_prefix() + "idle")
	if not sd.anim_is_playing(idle_anim):
		sd.anim_play(idle_anim, true)

	sd.velocity.x = 0.0
	sd._idle_elapsed += get_physics_process_delta_time()
	if sd._idle_elapsed >= WANDER_TRIGGER_DELAY:
		sd._is_wandering = true
		print("[SD:P12] IDLE→WANDER: idle_t=%.2f" % sd._idle_elapsed)
		return RUNNING

	# 每 120 帧打印兜底 idle 原因日志
	if Engine.get_physics_frames() % 120 == 0:
		print("[SD:P11] IDLE: aggro=%s full=%s knife=%s float=%s hp=%d" % [
			sd._aggro_mode, sd._is_full, sd._has_knife,
			sd._is_floating_invisible, sd.hp])
	return RUNNING


func interrupt(actor: Node, blackboard: Blackboard) -> void:
	var sd: SoulDevourer = actor as SoulDevourer
	if sd != null:
		sd.velocity.x = 0.0
		sd._idle_elapsed = 0.0
	super(actor, blackboard)
