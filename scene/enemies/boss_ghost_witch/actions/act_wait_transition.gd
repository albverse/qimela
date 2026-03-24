## 变身等待 Action：变身动画播放期间保持 RUNNING
extends ActionLeaf
class_name ActWaitTransition

func tick(actor: Node, _bb: Blackboard) -> int:
	var boss := actor as BossGhostWitch
	if boss == null:
		return FAILURE
	actor.velocity.x = 0.0
	if boss._phase_transitioning:
		if Engine.get_physics_frames() % 120 == 0:
			print("[ACT_WAIT_TRANSITION_DIAG] RUNNING: phase=%d transitioning=%s waiting_gate=%s anim=%s anim_finished=%s" % [boss.current_phase, boss._phase_transitioning, boss._waiting_phase3_gate, boss._current_anim, boss._current_anim_finished])
		return RUNNING  # 变身动画还没播完，保持 RUNNING
	return FAILURE  # 变身结束，让 CondPhaseTransitioning 失败，退出此分支


func interrupt(actor: Node, blackboard: Blackboard) -> void:
	# 安全清理：被高优先级分支打断时，确保变身标志不会永久卡住
	var boss := actor as BossGhostWitch
	if boss != null and boss._phase_transitioning:
		push_warning("[ACT_WAIT_TRANSITION] interrupted during phase transition! Clearing _phase_transitioning to prevent permanent lock.")
		boss._phase_transitioning = false
		boss.hp_locked = false
	super(actor, blackboard)
