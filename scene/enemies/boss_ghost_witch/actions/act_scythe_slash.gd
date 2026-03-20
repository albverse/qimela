extends ActionLeaf
class_name ActScytheSlash

## Phase 2 镰刀斩

enum Step { PLAY, WAIT }
var _step: int = Step.PLAY

func before_run(actor: Node, _bb: Blackboard) -> void:
	_step = Step.PLAY

func tick(actor: Node, blackboard: Blackboard) -> int:
	var boss: BossGhostWitch = actor as BossGhostWitch
	if boss == null:
		return FAILURE
	match _step:
		Step.PLAY:
			var player: Node2D = boss.get_priority_attack_target()
			if player:
				boss.face_toward(player)
			boss.anim_play(&"phase2/scythe_slash", false)
			_step = Step.WAIT
			return RUNNING
		Step.WAIT:
			if boss.anim_is_finished(&"phase2/scythe_slash"):
				_set_cooldown(actor, blackboard, "cd_scythe", boss.scythe_slash_cooldown)
				return SUCCESS
			return RUNNING
	return FAILURE

func _set_cooldown(actor: Node, bb: Blackboard, key: String, cd: float) -> void:
	bb.set_value(key, Time.get_ticks_msec() + cd * 1000.0, str(actor.get_instance_id()))

func interrupt(actor: Node, blackboard: Blackboard) -> void:
	_step = Step.PLAY
	super(actor, blackboard)
