extends ActionLeaf
class_name ActSoulDevourerIdle

## =============================================================================
## act_idle — 兜底待机（P11，永远返回 RUNNING）
## =============================================================================

func before_run(actor: Node, _blackboard: Blackboard) -> void:
	var sd: SoulDevourer = actor as SoulDevourer
	if sd == null:
		return
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
	return RUNNING


func interrupt(actor: Node, blackboard: Blackboard) -> void:
	var sd: SoulDevourer = actor as SoulDevourer
	if sd != null:
		sd.velocity.x = 0.0
	super(actor, blackboard)
