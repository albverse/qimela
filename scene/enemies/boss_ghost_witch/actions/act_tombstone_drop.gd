extends ActionLeaf
class_name ActTombstoneDrop

## 飞天砸落：起手施法 → 瞬移 → 渐显 → 悬停 → 投掷 → 下落 → 落地 → 僵直

enum Step { CAST, TELEPORT, APPEAR, HOVER, THROW, FALLING, LAND, STAGGER }

var _step: int = Step.CAST
var _target_pos: Vector2 = Vector2.ZERO
var _fall_timer: float = 0.0
var _hover_end: float = 0.0
var _stagger_end: float = 0.0
var _hitbox_frame_count: int = 0
var _appear_started: bool = false
var _land_started: bool = false

func before_run(actor: Node, _bb: Blackboard) -> void:
	_step = Step.CAST
	_hitbox_frame_count = 0
	_appear_started = false
	_land_started = false

func tick(actor: Node, blackboard: Blackboard) -> int:
	var boss: BossGhostWitch = actor as BossGhostWitch
	if boss == null:
		return FAILURE
	var dt: float = get_physics_process_delta_time()

	match _step:
		Step.CAST:
			boss.anim_play(&"phase2/tombstone_cast", false)
			var player: Node2D = boss.get_priority_attack_target()
			if player == null:
				return FAILURE
			var offset_x: float = boss.tombstone_offset_x_range * (1.0 if randf() > 0.5 else -1.0)
			_target_pos = Vector2(
				player.global_position.x + offset_x,
				player.global_position.y - boss.tombstone_offset_y
			)
			_step = Step.TELEPORT
			return RUNNING

		Step.TELEPORT:
			if boss.anim_is_finished(&"phase2/tombstone_cast"):
				actor.global_position = _target_pos
				actor.velocity = Vector2.ZERO
				_step = Step.APPEAR
			return RUNNING

		Step.APPEAR:
			if not _appear_started:
				boss.anim_play(&"phase2/tombstone_appear", false)
				_appear_started = true
			if boss.anim_is_finished(&"phase2/tombstone_appear"):
				_step = Step.HOVER
				_hover_end = Time.get_ticks_msec() + boss.tombstone_hover_duration * 1000.0
			return RUNNING

		Step.HOVER:
			boss.anim_play(&"phase2/tombstone_hover", true)
			if Time.get_ticks_msec() >= _hover_end:
				_step = Step.THROW
			return RUNNING

		Step.THROW:
			boss.anim_play(&"phase2/tombstone_throw", false)
			if boss.anim_is_finished(&"phase2/tombstone_throw"):
				_fall_timer = 0.0
				_step = Step.FALLING
			return RUNNING

		Step.FALLING:
			boss.anim_play(&"phase2/tombstone_fall", true)
			_fall_timer += dt
			var t_ratio: float = clampf(_fall_timer / boss.tombstone_fall_duration, 0.0, 1.0)
			var eased: float = t_ratio * t_ratio
			actor.velocity.y = eased * 2000.0
			if actor.is_on_floor():
				_step = Step.LAND
				_hitbox_frame_count = 0
			return RUNNING

		Step.LAND:
			actor.velocity = Vector2.ZERO
			if not _land_started:
				boss.anim_play(&"phase2/tombstone_land", false)
				_land_started = true
			if _hitbox_frame_count == 0:
				boss._set_hitbox_enabled(boss._ground_hitbox, true)
			elif _hitbox_frame_count >= 2:
				boss._set_hitbox_enabled(boss._ground_hitbox, false)
				_stagger_end = Time.get_ticks_msec() + boss.tombstone_stagger_duration * 1000.0
				_step = Step.STAGGER
			_hitbox_frame_count += 1
			return RUNNING

		Step.STAGGER:
			if Time.get_ticks_msec() >= _stagger_end:
				_set_cooldown(actor, blackboard, "cd_tombstone", boss.tombstone_drop_cooldown)
				return SUCCESS
			return RUNNING
	return FAILURE

func _set_cooldown(actor: Node, bb: Blackboard, key: String, cd: float) -> void:
	bb.set_value(key, Time.get_ticks_msec() + cd * 1000.0, str(actor.get_instance_id()))

func interrupt(actor: Node, blackboard: Blackboard) -> void:
	_step = Step.CAST
	_hitbox_frame_count = 0
	_appear_started = false
	_land_started = false
	var boss: BossGhostWitch = actor as BossGhostWitch
	if boss:
		boss._set_hitbox_enabled(boss._ground_hitbox, false)
		actor.velocity = Vector2.ZERO
	super(actor, blackboard)
