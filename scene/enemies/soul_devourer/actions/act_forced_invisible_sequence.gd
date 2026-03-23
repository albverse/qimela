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
	print("[SD:P5] before_run: current=%s full=%s aggro=%s wander=%s forced=%s float=%s" % [
		sd._current_anim, sd._is_full, sd._aggro_mode, sd._is_wandering, sd._forced_invisible, sd._is_floating_invisible])
	sd._enter_forced_invisible()


func tick(actor: Node, _blackboard: Blackboard) -> int:
	var sd: SoulDevourer = actor as SoulDevourer
	if sd == null:
		return FAILURE

	# 根因修复：Reactive Selector 切分支时，旧分支 cleanup 可能把当前轨道改回 idle，
	# 于是 P5 Action 仍在 RUNNING，但等待的 forced_invisible 动画其实已不在播。
	# 这里持续轮询并夺回起手动画轨道，直到真正播完为止。
	if not sd.anim_is_playing(&"normal/forced_invisible") and not sd.anim_is_finished(&"normal/forced_invisible"):
		if Engine.get_physics_frames() % 10 == 0:
			print("[SD:P5] STARTUP LOST: current=%s forced=%s forced_anim=%s float=%s full=%s aggro=%s" % [
				sd._current_anim, sd._forced_invisible, sd._forced_invisible_anim_playing, sd._is_floating_invisible, sd._is_full, sd._aggro_mode])
		if not sd.anim_play(&"normal/forced_invisible", false) and Engine.get_physics_frames() % 15 == 0:
			print("[SD:P5] WAIT STARTUP: anim blocked, current=%s hurt=%.2f forced=%s float=%s" % [
				sd._current_anim, sd._hurt_timer, sd._forced_invisible, sd._is_floating_invisible])

	if sd.anim_is_finished(&"normal/forced_invisible"):
		sd._complete_forced_invisible_animation()
		# 动画结束后才正式进入漂浮隐身态
		sd.anim_play(&"normal/float_idle", true)
		return SUCCESS

	return RUNNING


func interrupt(actor: Node, blackboard: Blackboard) -> void:
	var sd: SoulDevourer = actor as SoulDevourer
	if sd != null and sd.is_forced_invisible_anim_playing():
		print("[SD:P5] interrupt IGNORED: current=%s forced=%s float=%s" % [
			sd._current_anim, sd._forced_invisible, sd._is_floating_invisible])
		# 强制隐身起手动画不可被更高优先级的漂浮分支抢断。
		return
	super(actor, blackboard)
