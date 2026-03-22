extends ActionLeaf
class_name ActSoulDevourerDeathRebirthFlow

## =============================================================================
## act_death_rebirth_flow — 管理完整 death-rebirth 流程
## =============================================================================
## 内部状态：PLAY_WEAK_KNIFE → PLAY_DEATH → HIDDEN_WAIT → PLAY_BORN → DONE
## 返回 RUNNING 直到 DONE（重置后由 cond_death_rebirth_active 返回 FAILURE 退出）
## =============================================================================

enum Phase {
	PLAY_WEAK_KNIFE = 0,  # 持刀 weak 动画（掉刀）
	PLAY_DEATH = 1,       # 死亡动画
	HIDDEN_WAIT = 2,      # 隐藏等待（10 秒）
	PLAY_BORN = 3,        # 重生动画
	DONE = 4,             # 完成
}

var _phase: int = Phase.PLAY_WEAK_KNIFE
var _phase_entered: bool = false


func before_run(actor: Node, _blackboard: Blackboard) -> void:
	_phase = Phase.PLAY_WEAK_KNIFE
	_phase_entered = false


func tick(actor: Node, _blackboard: Blackboard) -> int:
	var sd: SoulDevourer = actor as SoulDevourer
	if sd == null:
		return FAILURE

	match _phase:
		Phase.PLAY_WEAK_KNIFE:
			if not _phase_entered:
				_phase_entered = true
				if sd._has_knife:
					sd.anim_play(&"has_knife/weak", false)
				else:
					# 无刀直接跳到 death
					_advance_phase(sd)
					return RUNNING
			# 等待 has_knife/weak 播完（spawn_cleaver 事件已在动画中触发）
			if sd._has_knife:
				if sd.anim_is_finished(&"has_knife/weak"):
					sd._has_knife = false
					_advance_phase(sd)
			else:
				_advance_phase(sd)
			return RUNNING

		Phase.PLAY_DEATH:
			if not _phase_entered:
				_phase_entered = true
				sd.anim_play(&"normal/death", false)
			if sd.anim_is_finished(&"normal/death"):
				sd._finish_death_and_hide()
				_advance_phase(sd)
			return RUNNING

		Phase.HIDDEN_WAIT:
			# 等待 _respawn_from_spawn_point 被计时器调用（_is_respawning 变为 true）
			if sd._is_respawning:
				_advance_phase(sd)
			return RUNNING

		Phase.PLAY_BORN:
			if not _phase_entered:
				_phase_entered = true
				# _respawn_from_spawn_point 已播放 born，此处只检测完成
			if sd.anim_is_finished(&"normal/born"):
				sd.death_rebirth_on_born_finished()
				_phase = Phase.DONE
			return RUNNING

		Phase.DONE:
			# 重置后 _death_rebirth_started = false，cond 返回 FAILURE，行为树回落 idle
			return SUCCESS

	return RUNNING


func _advance_phase(sd: SoulDevourer) -> void:
	_phase += 1
	_phase_entered = false


func interrupt(actor: Node, blackboard: Blackboard) -> void:
	# death-rebirth 不可被打断，但 Beehave 框架可能调用 interrupt
	# 不清除状态，下帧 cond 仍返回 SUCCESS，此 Action 继续执行
	super(actor, blackboard)
