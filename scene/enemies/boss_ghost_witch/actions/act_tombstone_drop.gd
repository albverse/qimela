## 起手施法 → 平滑上升到玩家头上 → 悬停 → 幽灵投掷 → 下落 → 落地冲击 → 僵直
extends ActionLeaf
class_name ActTombstoneDrop

enum Step {
	CAST,           # 地面起手施法动画
	RISE,           # 施法播完 → 平滑上升到目标位置（替代瞬移）
	HOVER,          # 空中静止悬停（短暂压迫感）
	THROW,          # 被幽灵向下投掷的瞬间（发力表现）
	FALLING,        # 高速下落循环
	LAND,           # 砸到地面（冲击 + 范围伤害）
	STAGGER,        # 僵直
}

var _step: int = Step.CAST
var _target_pos: Vector2 = Vector2.ZERO
var _ground_y: float = 0.0        # 施法时记录的地面 Y 坐标
var _rise_origin: Vector2 = Vector2.ZERO
var _rise_timer: float = 0.0
var _fall_timer: float = 0.0
var _hover_end: float = 0.0
var _stagger_end: float = 0.0
var _hitbox_frame_count: int = 0

func before_run(actor: Node, _bb: Blackboard) -> void:
	_step = Step.CAST
	_hitbox_frame_count = 0
	_rise_timer = 0.0
	_fall_timer = 0.0
	_ground_y = 0.0
	_hover_end = 0.0
	_stagger_end = 0.0

func tick(actor: Node, blackboard: Blackboard) -> int:
	var boss := actor as BossGhostWitch
	if boss == null:
		return FAILURE
	var dt := get_physics_process_delta_time()

	match _step:
		Step.CAST:
			boss.anim_play(&"phase2/tombstone_cast", false)
			var player := boss.get_priority_attack_target()
			if player == null:
				return FAILURE
			# 记录地面 Y（Boss 此时站在地面）
			_ground_y = actor.global_position.y
			var offset_x := boss.tombstone_offset_x_range * (1.0 if randf() > 0.5 else -1.0)
			_target_pos = Vector2(
				player.global_position.x + offset_x,
				player.global_position.y - boss.tombstone_offset_y
			)
			_step = Step.RISE
			return RUNNING

		Step.RISE:
			if not boss.anim_is_finished(&"phase2/tombstone_cast"):
				return RUNNING
			# 首次进入 RISE：跳过基础物理（重力+碰撞），切换到上升动画
			if _rise_timer == 0.0:
				boss.skip_gravity_and_move = true
				_rise_origin = actor.global_position
				boss.anim_play(&"phase2/tombstone_rise", true)
			actor.velocity = Vector2.ZERO
			_rise_timer += dt
			var t := clampf(_rise_timer / boss.tombstone_rise_duration, 0.0, 1.0)
			# ease-out 曲线：快速起步，缓慢到达
			var eased := 1.0 - (1.0 - t) * (1.0 - t)
			actor.global_position = _rise_origin.lerp(_target_pos, eased)
			if t >= 1.0:
				actor.global_position = _target_pos
				_hover_end = Time.get_ticks_msec() + boss.tombstone_hover_duration * 1000.0
				_step = Step.HOVER
			return RUNNING


		Step.HOVER:
			actor.velocity = Vector2.ZERO
			boss.anim_play(&"phase2/tombstone_hover", true)
			if Time.get_ticks_msec() >= _hover_end:
				_step = Step.THROW
			return RUNNING

		Step.THROW:
			actor.velocity = Vector2.ZERO
			boss.anim_play(&"phase2/tombstone_throw", false)
			if boss.anim_is_finished(&"phase2/tombstone_throw"):
				_fall_timer = 0.0
				_step = Step.FALLING
			return RUNNING

		Step.FALLING:
			actor.velocity = Vector2.ZERO
			boss.anim_play(&"phase2/tombstone_fall", true)
			_fall_timer += dt
			var t_ratio := clampf(_fall_timer / boss.tombstone_fall_duration, 0.0, 1.0)
			var eased := t_ratio * t_ratio
			var fall_speed := eased * 2000.0
			# 直接修改 global_position，绕过 move_and_slide 碰撞
			actor.global_position.y += fall_speed * dt

			# 下落期间检测伤害（monitoring 由 Spine 事件控制）
			if boss._ground_hitbox.monitoring:
				for body in boss._ground_hitbox.get_overlapping_bodies():
					if body.is_in_group("player") and body.has_method("apply_damage"):
						body.call("apply_damage", 1, actor.global_position)

			# 到达地面或超时（3 秒保底）
			if actor.global_position.y >= _ground_y or _fall_timer > 3.0:
				actor.global_position.y = _ground_y
				_step = Step.LAND
				_hitbox_frame_count = 0
				# 恢复基础物理（重力+碰撞）
				boss.skip_gravity_and_move = false
			return RUNNING

		Step.LAND:
			actor.velocity = Vector2.ZERO
			boss.anim_play(&"phase2/tombstone_land", false)
			if _hitbox_frame_count == 0:
				boss._set_hitbox_enabled(boss._ground_hitbox, true)
			elif _hitbox_frame_count >= 2:
				boss._set_hitbox_enabled(boss._ground_hitbox, false)
				_stagger_end = Time.get_ticks_msec() + boss.tombstone_stagger_duration * 1000.0
				_step = Step.STAGGER
			_hitbox_frame_count += 1
			return RUNNING

		Step.STAGGER:
			if boss.anim_is_finished(&"phase2/tombstone_land"):
				boss.anim_play(&"phase2/idle", true)
			if Time.get_ticks_msec() >= _stagger_end:
				_set_cooldown(actor, blackboard, "cd_tombstone", boss.tombstone_drop_cooldown)
				return SUCCESS
			return RUNNING
	return FAILURE

func _set_cooldown(actor: Node, bb: Blackboard, key: String, cd: float) -> void:
	bb.set_value(key, Time.get_ticks_msec() + cd * 1000.0, str(actor.get_instance_id()))

func interrupt(actor: Node, blackboard: Blackboard) -> void:
	var boss := actor as BossGhostWitch
	if boss:
		boss._set_hitbox_enabled(boss._ground_hitbox, false)
		actor.velocity = Vector2.ZERO
		# 恢复基础物理
		boss.skip_gravity_and_move = false
		# 恢复到地面位置（防止中断时卡在空中）
		if _ground_y > 0.0 and actor.global_position.y < _ground_y:
			actor.global_position.y = _ground_y
	_step = Step.CAST
	_hitbox_frame_count = 0
	super(actor, blackboard)
