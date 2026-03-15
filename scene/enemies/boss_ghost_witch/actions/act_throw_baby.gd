extends ActionLeaf
class_name ActThrowBaby

## 播放抛婴儿动画 → 婴儿飞向玩家 → 进入 THROWN 状态

enum Step { ANIM_THROW, WAIT_ANIM, BABY_FLYING }
var _step: int = Step.ANIM_THROW

func before_run(actor: Node, _bb: Blackboard) -> void:
	_step = Step.ANIM_THROW

func tick(actor: Node, blackboard: Blackboard) -> int:
	var boss: BossGhostWitch = actor as BossGhostWitch
	if boss == null:
		return FAILURE
	var actor_id: String = str(actor.get_instance_id())
	var player: Node2D = blackboard.get_value("player", null, actor_id)

	match _step:
		Step.ANIM_THROW:
			if player == null:
				return FAILURE
			boss.anim_play(&"phase1/throw", false)
			_step = Step.WAIT_ANIM
			return RUNNING
		Step.WAIT_ANIM:
			if boss.baby_state == BossGhostWitch.BabyState.THROWN:
				boss.baby_anim_play(&"baby/spin", true)
				_step = Step.BABY_FLYING
			elif boss.anim_is_finished(&"phase1/throw"):
				boss._on_baby_release()
				boss.baby_anim_play(&"baby/spin", true)
				_step = Step.BABY_FLYING
			return RUNNING
		Step.BABY_FLYING:
			if boss.baby_state != BossGhostWitch.BabyState.THROWN:
				return SUCCESS
			return RUNNING
	return FAILURE

func interrupt(actor: Node, blackboard: Blackboard) -> void:
	_step = Step.ANIM_THROW
	super(actor, blackboard)
