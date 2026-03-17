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
	actor.velocity.x = 0.0
	var actor_id := str(actor.get_instance_id())
	var player: Node2D = blackboard.get_value("player", null, actor_id)

	match _step:
		Step.ANIM_THROW:
			if player == null:
				return FAILURE
			_target_pos = player.global_position
			# 提前设置飞行目标，因为 baby_release 后 CondBabyInHug 失败会中断本 Action
			boss._baby_flight_target = _target_pos
			print("[ACT_THROW_BABY_DEBUG] sample_target at cast_start player=%s boss=%s target=%s" % [player.global_position, boss.global_position, _target_pos])
			boss.face_toward(player)
			boss.anim_play(&"phase1/throw", false)
			_step = Step.WAIT_ANIM
			return RUNNING
		Step.WAIT_ANIM:
			# 等待 Spine 事件 "baby_release" 触发
			# 事件回调中会设置 boss.baby_state = BabyState.THROWN
			# 此时 CondBabyInHug 会失败，SequenceReactive 会中断本 Action
			# 飞行移动由 boss._tick_baby_flight() 在 _physics_process 中处理
			if boss.baby_state == BossGhostWitch.BabyState.THROWN:
				_step = Step.BABY_FLYING
			return RUNNING
		Step.BABY_FLYING:
			# 飞行移动由 boss._tick_baby_flight() 在 _physics_process 中处理
			# 婴儿到达目标 → 自动进入 EXPLODED
			if boss.baby_state != BossGhostWitch.BabyState.THROWN:
				return SUCCESS
			return RUNNING
	return FAILURE

func interrupt(actor: Node, blackboard: Blackboard) -> void:
	_step = Step.ANIM_THROW
	if actor != null:
		actor.velocity.x = 0.0
	super(actor, blackboard)
