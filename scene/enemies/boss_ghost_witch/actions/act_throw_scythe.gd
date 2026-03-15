extends ActionLeaf
class_name ActThrowScythe

## Phase 3 扔镰刀（兜底技能）：扔出 → 站桩等待 → 被打回航 → 接住

enum Step { THROW_ANIM, SCYTHE_OUT, RECALL_WAIT, CATCH }
var _step: int = Step.THROW_ANIM
var _throw_started: bool = false

func before_run(actor: Node, _bb: Blackboard) -> void:
	_step = Step.THROW_ANIM
	_throw_started = false

func tick(actor: Node, _blackboard: Blackboard) -> int:
	var boss: BossGhostWitch = actor as BossGhostWitch
	if boss == null:
		return FAILURE

	match _step:
		Step.THROW_ANIM:
			if not _throw_started:
				var player: Node2D = boss.get_priority_attack_target()
				if player:
					boss.face_toward(player)
				boss.anim_play(&"phase3/throw_scythe", false)
				_throw_started = true
			if boss.anim_is_finished(&"phase3/throw_scythe"):
				_spawn_scythe(boss)
				_step = Step.SCYTHE_OUT
			return RUNNING

		Step.SCYTHE_OUT:
			boss.anim_play(&"phase3/idle_no_scythe", true)
			boss.velocity.x = 0.0
			if boss._scythe_recall_requested:
				boss._scythe_recall_requested = false
				_recall_scythe(boss)
				_step = Step.RECALL_WAIT
			elif boss._scythe_instance == null or not is_instance_valid(boss._scythe_instance):
				boss._scythe_in_hand = true
				boss.anim_play(&"phase3/catch_scythe", false)
				_step = Step.CATCH
			return RUNNING

		Step.RECALL_WAIT:
			boss.anim_play(&"phase3/idle_no_scythe", true)
			boss.velocity.x = 0.0
			if boss._scythe_instance == null or not is_instance_valid(boss._scythe_instance):
				boss._scythe_in_hand = true
				boss.anim_play(&"phase3/catch_scythe", false)
				_step = Step.CATCH
			return RUNNING

		Step.CATCH:
			if boss.anim_is_finished(&"phase3/catch_scythe"):
				return SUCCESS
			return RUNNING
	return FAILURE

func _spawn_scythe(boss: BossGhostWitch) -> void:
	var scythe: Node2D = (boss._witch_scythe_scene as PackedScene).instantiate()
	scythe.add_to_group("witch_scythe")
	var player: Node2D = boss.get_priority_attack_target()
	if scythe.has_method("setup"):
		scythe.call("setup", player, boss,
			boss.p3_scythe_track_interval,
			boss.p3_scythe_track_count,
			boss.p3_scythe_fly_speed,
			boss.p3_scythe_return_speed)
	scythe.global_position = boss.global_position
	boss.get_parent().add_child(scythe)
	boss._scythe_instance = scythe
	boss._scythe_in_hand = false

func _recall_scythe(boss: BossGhostWitch) -> void:
	if boss._scythe_instance != null and is_instance_valid(boss._scythe_instance):
		if boss._scythe_instance.has_method("recall"):
			boss._scythe_instance.call("recall", boss.global_position)

func interrupt(actor: Node, blackboard: Blackboard) -> void:
	_step = Step.THROW_ANIM
	_throw_started = false
	super(actor, blackboard)
