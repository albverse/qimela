extends ActionLeaf
class_name ActSoulDevourerForcedInvisibleSequence

## =============================================================================
## act_forced_invisible_sequence — 强制隐身触发序列（P5）
## =============================================================================
## 玩家贴脸时触发：播放 normal/forced_invisible → 进入漂浮隐身态。
## 动画完成后此 Action 返回 SUCCESS，漂浮行为由 P4 接管。
## =============================================================================

func before_run(actor: Node, _blackboard: Blackboard) -> void:
	var sd: SoulDevourer = actor as SoulDevourer
	if sd == null:
		return
	sd._enter_forced_invisible()


func tick(actor: Node, _blackboard: Blackboard) -> int:
	var sd: SoulDevourer = actor as SoulDevourer
	if sd == null:
		return FAILURE

	# 等待 forced_invisible 动画播完
	if sd.anim_is_finished(&"normal/forced_invisible"):
		# 动画结束后切换到漂浮 idle
		sd.anim_play(&"normal/float_idle", true)
		return SUCCESS

	return RUNNING


func interrupt(actor: Node, blackboard: Blackboard) -> void:
	super(actor, blackboard)
