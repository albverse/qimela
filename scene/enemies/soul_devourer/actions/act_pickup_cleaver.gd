extends ActionLeaf
class_name ActSoulDevourerPickupCleaver

## =============================================================================
## act_pickup_cleaver — 移动到最近 SoulCleaver 并拾取（P6）
## =============================================================================
## 到达刀的位置 → 播放 normal/change_to_has_knife
##   → Spine 事件 cleaver_pick → 立即销毁刀
##   → animation_completed → _has_knife = true
## 超时 5.0s → FAILURE
## =============================================================================

const PICKUP_REACH_DIST: float = 32.0
const COOLDOWN_KEY: StringName = &"sd_cleaver_pickup_cd_end"

enum Phase {
	MOVE_TO_CLEAVER = 0,
	PLAY_PICKUP_ANIM = 1,
}

var _phase: int = Phase.MOVE_TO_CLEAVER
var _timer: float = 0.0


func before_run(actor: Node, _blackboard: Blackboard) -> void:
	_phase = Phase.MOVE_TO_CLEAVER
	_timer = 0.0
	var sd: SoulDevourer = actor as SoulDevourer
	if sd == null:
		return
	# 锁定目标刀
	var cleaver: SoulCleaver = sd._find_nearest_cleaver()
	if cleaver != null:
		cleaver.claimed = true
		sd._current_target_cleaver = cleaver
	sd.anim_play(&"normal/run", true)


func tick(actor: Node, blackboard: Blackboard) -> int:
	var sd: SoulDevourer = actor as SoulDevourer
	if sd == null:
		return FAILURE

	var dt: float = get_physics_process_delta_time()
	_timer += dt

	if _timer >= sd.move_to_cleaver_timeout:
		_cleanup(sd)
		return FAILURE

	match _phase:
		Phase.MOVE_TO_CLEAVER:
			return _tick_move(sd, dt)
		Phase.PLAY_PICKUP_ANIM:
			return _tick_pickup_anim(sd, blackboard)

	return RUNNING


func _tick_move(sd: SoulDevourer, _dt: float) -> int:
	# 目标刀消失（被销毁或无效）
	if sd._current_target_cleaver == null or not is_instance_valid(sd._current_target_cleaver):
		sd._current_target_cleaver = null
		return FAILURE

	var cleaver_pos: Vector2 = sd._current_target_cleaver.global_position
	var dist: float = sd.global_position.distance_to(cleaver_pos)

	if dist <= PICKUP_REACH_DIST:
		# 到达，播放拾取动画
		_phase = Phase.PLAY_PICKUP_ANIM
		sd.velocity.x = 0.0
		sd.anim_play(&"normal/change_to_has_knife", false)
		return RUNNING

	# 移动朝向
	var dir: float = sign(cleaver_pos.x - sd.global_position.x)
	sd.velocity.x = dir * sd.ground_run_speed
	# 翻转朝向
	if dir != 0.0:
		sd.scale.x = abs(sd.scale.x) * dir
	sd.move_and_slide()
	return RUNNING


func _tick_pickup_anim(sd: SoulDevourer, blackboard: Blackboard) -> int:
	# cleaver_pick 事件已在 SoulDevourer._on_spine_event_cleaver_pick 处理
	if sd.anim_is_finished(&"normal/change_to_has_knife"):
		# 动画完成 → 正式持刀
		sd._has_knife = true
		# 设置技能 CD
		var actor_id: String = str(sd.get_instance_id())
		blackboard.set_value(COOLDOWN_KEY, SoulDevourer.now_sec() + sd.skill_cooldown_has_knife, actor_id)
		return SUCCESS
	return RUNNING


func _cleanup(sd: SoulDevourer) -> void:
	if sd._current_target_cleaver != null and is_instance_valid(sd._current_target_cleaver):
		sd._current_target_cleaver.claimed = false
	sd._current_target_cleaver = null
	sd.velocity.x = 0.0


func interrupt(actor: Node, blackboard: Blackboard) -> void:
	var sd: SoulDevourer = actor as SoulDevourer
	if sd != null:
		_cleanup(sd)
	super(actor, blackboard)
