## 扔出镰刀 → 本体站桩等待 → 被打则镰刀回航 → 接住 → 结束
extends ActionLeaf
class_name ActThrowScythe

enum Step { THROW_ANIM, SCYTHE_OUT, RECALL_WAIT, CATCH, DONE }
var _step: int = Step.THROW_ANIM

func before_run(actor: Node, _bb: Blackboard) -> void:
	_step = Step.THROW_ANIM

func tick(actor: Node, _blackboard: Blackboard) -> int:
	var boss := actor as BossGhostWitch
	if boss == null:
		return FAILURE
	actor.velocity.x = 0.0

	match _step:
		Step.THROW_ANIM:
			var player := boss.get_priority_attack_target()
			if player:
				boss.face_toward(player)
			boss.anim_play(&"phase3/throw_scythe", false)
			_step = Step.SCYTHE_OUT
			return RUNNING

		Step.SCYTHE_OUT:
			if boss._scythe_instance == null and boss.anim_is_finished(&"phase3/throw_scythe"):
				_spawn_scythe(boss)
			elif boss._scythe_instance == null:
				return RUNNING

			# 镰刀在外，本体原地待机
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
	var scythe: Node2D = boss._witch_scythe_scene.instantiate()
	scythe.add_to_group("witch_scythe")
	var player := boss.get_priority_attack_target()
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
	super(actor, blackboard)
