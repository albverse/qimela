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

const PICKUP_REACH_DIST: float = 10.0
const PICKUP_REACH_GRACE: float = 18.0
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
		print("[SD:P6] before_run: cleaver at %s, sd at %s, dist=%.1f" % [
			cleaver.global_position, sd.global_position,
			sd.global_position.distance_to(cleaver.global_position)])
	else:
		print("[SD:P6] before_run: NO cleaver found")
	sd.anim_play(&"normal/run", true)


func tick(actor: Node, blackboard: Blackboard) -> int:
	var sd: SoulDevourer = actor as SoulDevourer
	if sd == null:
		return FAILURE

	var dt: float = get_physics_process_delta_time()
	_timer += dt

	if _timer >= sd.move_to_cleaver_timeout:
		print("[SD:P6] TIMEOUT (%.1fs)" % _timer)
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
		print("[SD:P6] MOVE: cleaver LOST")
		sd._current_target_cleaver = null
		return FAILURE

	var cleaver_pos: Vector2 = sd._current_target_cleaver.global_position
	var dist: float = sd.global_position.distance_to(cleaver_pos)
	var reach_dist: float = absf(sd.global_position.x - cleaver_pos.x)
	var pickup_reach: float = _get_pickup_reach(sd._current_target_cleaver)

	if reach_dist <= pickup_reach:
		# 到达，播放拾取动画；重置计时器给动画独立的时间窗口
		print("[SD:P6] MOVE→PICKUP: reach=%.1f/%.1f, eucl=%.1f, sd=%s, cleaver=%s (move_t=%.1fs)" % [
			reach_dist, pickup_reach, dist, sd.global_position, cleaver_pos, _timer])
		_phase = Phase.PLAY_PICKUP_ANIM
		_timer = 0.0  # 重置：移动阶段耗时不计入拾取动画超时
		sd.velocity.x = 0.0
		sd._pickup_anim_playing = true
		if not sd.anim_play(&"normal/change_to_has_knife", false):
			print("[SD:P6] PICKUP ANIM BLOCKED by hurt: anim=%s, hurt_timer=%.2f" % [
				sd._current_anim, sd._hurt_timer])
		return RUNNING

	# 移动朝向
	var dir: float = sign(cleaver_pos.x - sd.global_position.x)
	sd.velocity.x = dir * sd.ground_run_speed
	sd.face_toward_position(cleaver_pos.x)
	# 每 30 帧打印一次距离日志
	if Engine.get_physics_frames() % 30 == 0:
		print("[SD:P6] MOVE: reach=%.1f/%.1f, eucl=%.1f, vel.x=%.1f, sd=%s, cleaver=%s" % [
			reach_dist, pickup_reach, dist, sd.velocity.x, sd.global_position, cleaver_pos])
	# move_and_slide 由 _physics_process 统一调用
	return RUNNING


func _tick_pickup_anim(sd: SoulDevourer, blackboard: Blackboard) -> int:
	sd.velocity.x = 0.0
	# cleaver_pick 事件已在 SoulDevourer._on_spine_event_cleaver_pick 处理
	if not sd.anim_is_playing(&"normal/change_to_has_knife") and not sd.anim_is_finished(&"normal/change_to_has_knife"):
		if not sd.anim_play(&"normal/change_to_has_knife", false):
			if Engine.get_physics_frames() % 15 == 0:
				print("[SD:P6] WAIT PICKUP ANIM: blocked by hurt, current=%s, hurt_timer=%.2f" % [
					sd._current_anim, sd._hurt_timer])
	if sd.anim_is_finished(&"normal/change_to_has_knife"):
		# 动画完成 → 正式持刀
		sd._has_knife = true
		sd._pickup_anim_playing = false
		print("[SD:P6] PICKUP DONE: has_knife=true")
		# 设置技能 CD
		var actor_id: String = str(sd.get_instance_id())
		blackboard.set_value(COOLDOWN_KEY, SoulDevourer.now_sec() + sd.skill_cooldown_has_knife, actor_id)
		return SUCCESS
	return RUNNING


func _cleanup(sd: SoulDevourer) -> void:
	if sd._current_target_cleaver != null and is_instance_valid(sd._current_target_cleaver):
		sd._current_target_cleaver.claimed = false
	sd._current_target_cleaver = null
	sd._pickup_anim_playing = false
	sd.velocity.x = 0.0


func _get_pickup_reach(cleaver: Node) -> float:
	var pickup_reach: float = PICKUP_REACH_DIST
	if cleaver != null and cleaver.has_method("get_pickup_radius"):
		pickup_reach = maxf(pickup_reach, float(cleaver.call("get_pickup_radius")))
	return pickup_reach + PICKUP_REACH_GRACE


func interrupt(actor: Node, blackboard: Blackboard) -> void:
	print("[SD:P6] INTERRUPTED")
	var sd: SoulDevourer = actor as SoulDevourer
	if sd != null:
		_cleanup(sd)
	super(actor, blackboard)
