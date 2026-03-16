## 播放抛婴儿动画 → 婴儿从 mark2D_hug 发射飞向玩家 → 进入 THROWN 状态
extends ActionLeaf
class_name ActThrowBaby

enum Step { ANIM_THROW, WAIT_ANIM, BABY_FLYING, DONE }
var _step: int = Step.ANIM_THROW
var _target_pos: Vector2 = Vector2.ZERO

func before_run(actor: Node, _bb: Blackboard) -> void:
	_step = Step.ANIM_THROW

func tick(actor: Node, blackboard: Blackboard) -> int:
	var boss := actor as BossGhostWitch
	if boss == null:
		return FAILURE
	var actor_id := str(actor.get_instance_id())
	var player: Node2D = blackboard.get_value("player", null, actor_id)

	match _step:
		Step.ANIM_THROW:
			if player == null:
				return FAILURE
			_target_pos = player.global_position
			boss.anim_play(&"phase1/throw", false)
			_step = Step.WAIT_ANIM
			return RUNNING
		Step.WAIT_ANIM:
			# 等待 Spine 事件 "baby_release" 触发
			# 事件回调中会设置 boss.baby_state = BabyState.THROWN
			if boss.baby_state == BossGhostWitch.BabyState.THROWN:
				_step = Step.BABY_FLYING
			return RUNNING
		Step.BABY_FLYING:
			# 婴儿飞行中播放旋转动画
			boss.baby_anim_play(&"baby/spin", true)
			# 婴儿撞到地面 → 自动进入 EXPLODED
			if boss.baby_state != BossGhostWitch.BabyState.THROWN:
				return SUCCESS
			return RUNNING
	return FAILURE

func interrupt(actor: Node, blackboard: Blackboard) -> void:
	_step = Step.ANIM_THROW
	super(actor, blackboard)
