extends ActionLeaf
class_name ActThrowScytheUpward

## Phase 3 禁锢反应（玩家在上方）：跑到玩家 X 位置 → 向上扔追踪镰刀

enum Step { RUN_TO_X, THROW_UP, WAIT_SCYTHE }
var _step: int = Step.RUN_TO_X
var _throw_started: bool = false

func before_run(actor: Node, _bb: Blackboard) -> void:
	_step = Step.RUN_TO_X
	_throw_started = false

func tick(actor: Node, _bb: Blackboard) -> int:
	var boss: BossGhostWitch = actor as BossGhostWitch
	if boss == null:
		return FAILURE

	match _step:
		Step.RUN_TO_X:
			var player: Node2D = boss.get_priority_attack_target()
			if player == null:
				return FAILURE
			var h_dist: float = abs(actor.global_position.x - player.global_position.x)
			if h_dist < 30.0:
				actor.velocity.x = 0.0
				_step = Step.THROW_UP
			else:
				var dir: float = signf(player.global_position.x - actor.global_position.x)
				actor.velocity.x = dir * boss.p3_run_speed
				boss.anim_play(&"phase3/walk", true)
			return RUNNING

		Step.THROW_UP:
			actor.velocity.x = 0.0
			if not _throw_started:
				boss.anim_play(&"phase3/throw_scythe", false)
				_throw_started = true
			if boss.anim_is_finished(&"phase3/throw_scythe"):
				_spawn_tracking_scythe(boss)
				_step = Step.WAIT_SCYTHE
			return RUNNING

		Step.WAIT_SCYTHE:
			boss.anim_play(&"phase3/idle_no_scythe", true)
			if boss._scythe_instance == null or not is_instance_valid(boss._scythe_instance):
				boss._scythe_in_hand = true
				boss.anim_play(&"phase3/catch_scythe", false)
				boss._player_imprisoned = false
				if boss._hell_hand_instance and is_instance_valid(boss._hell_hand_instance):
					boss._hell_hand_instance.queue_free()
				return SUCCESS
			return RUNNING
	return FAILURE

func _spawn_tracking_scythe(boss: BossGhostWitch) -> void:
	var scythe: Node2D = (boss._witch_scythe_scene as PackedScene).instantiate()
	scythe.add_to_group("witch_scythe")
	var player: Node2D = boss.get_priority_attack_target()
	if scythe.has_method("setup_tracking"):
		scythe.call("setup_tracking", player, boss, boss.p3_scythe_fly_speed)
	scythe.global_position = boss.global_position + Vector2(0, -50)
	boss.get_parent().add_child(scythe)
	boss._scythe_instance = scythe
	boss._scythe_in_hand = false

func interrupt(actor: Node, blackboard: Blackboard) -> void:
	actor.velocity.x = 0.0
	_step = Step.RUN_TO_X
	_throw_started = false
	super(actor, blackboard)
