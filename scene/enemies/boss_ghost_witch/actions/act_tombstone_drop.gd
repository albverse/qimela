extends ActionLeaf
class_name ActTombstoneDrop

enum Step { CAST_ANIM, FALLING, GROUND_HIT, STAGGER }
var _step: int = Step.CAST_ANIM
var _stagger_end_ms: float = 0.0
var _hitbox_frames: int = 0

func before_run(_actor: Node, _bb: Blackboard) -> void:
	_step = Step.CAST_ANIM
	_hitbox_frames = 0

func tick(actor: Node, blackboard: Blackboard) -> int:
	var boss := actor as BossGhostWitch
	if boss == null:
		return FAILURE
	match _step:
		Step.CAST_ANIM:
			boss.anim_play(&"phase2/tombstone_cast", false)
			if boss.anim_is_finished(&"phase2/tombstone_cast"):
				var p := boss.get_priority_attack_target()
				if p == null:
					return FAILURE
				actor.global_position = Vector2(
					p.global_position.x + randf_range(-boss.tombstone_offset_x_range, boss.tombstone_offset_x_range),
					p.global_position.y - boss.tombstone_offset_y
				)
				_step = Step.FALLING
		Step.FALLING:
			boss.velocity.y = 2000.0
			if boss.is_on_floor():
				boss.velocity = Vector2.ZERO
				boss.anim_play(&"phase2/tombstone_land", false)
				boss._set_hitbox_enabled(boss._ground_hitbox, true)
				_hitbox_frames = 1
				_step = Step.GROUND_HIT
		Step.GROUND_HIT:
			if _hitbox_frames > 0:
				_hitbox_frames -= 1
			else:
				boss._set_hitbox_enabled(boss._ground_hitbox, false)
				_stagger_end_ms = Time.get_ticks_msec() + boss.tombstone_stagger_duration * 1000.0
				_step = Step.STAGGER
		Step.STAGGER:
			if Time.get_ticks_msec() >= _stagger_end_ms:
				_set_cd(actor, blackboard, "cd_tombstone", boss.tombstone_drop_cooldown)
				return SUCCESS
	return RUNNING

func _set_cd(actor: Node, bb: Blackboard, key: String, cd: float) -> void:
	bb.set_value(key, Time.get_ticks_msec() + cd * 1000.0, str(actor.get_instance_id()))

func interrupt(actor: Node, blackboard: Blackboard) -> void:
	var boss := actor as BossGhostWitch
	if boss:
		boss._set_hitbox_enabled(boss._ground_hitbox, false)
	_step = Step.CAST_ANIM
	super(actor, blackboard)
