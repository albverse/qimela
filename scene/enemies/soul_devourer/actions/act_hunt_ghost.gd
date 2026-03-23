extends ActionLeaf
class_name ActSoulDevourerHuntGhost

## =============================================================================
## act_hunt_ghost — 猎杀幽灵（P9 aggro+notfull，P10 被动猎杀）
## =============================================================================
## - 地面显现态：播放 normal/huntting（循环），不复用 normal/run
## - 漂浮隐身态：播放 normal/float_move（循环）
## 到达吞食距离 → ghost.start_being_hunted() → huntting_succeed → _is_full=true
## 超时 hunt_timeout → FAILURE
## =============================================================================

const HUNT_REACH_DIST: float = 32.0
const HUNT_TRANSITION_DIST: float = 60.0  # 进入 huntting 动画的距离阈值

var _timer: float = 0.0
var _hunting_anim_active: bool = false


func before_run(actor: Node, _blackboard: Blackboard) -> void:
	_timer = 0.0
	_hunting_anim_active = false
	var sd: SoulDevourer = actor as SoulDevourer
	if sd == null:
		return
	# 查找并锁定猎物
	var ghost: Node2D = sd._find_nearest_huntable_ghost()
	sd._current_target_ghost = ghost
	if ghost == null:
		return
	_play_hunt_anim(sd)


func tick(actor: Node, _blackboard: Blackboard) -> int:
	var sd: SoulDevourer = actor as SoulDevourer
	if sd == null:
		return FAILURE

	var dt: float = get_physics_process_delta_time()
	_timer += dt

	# 超时兜底
	if _timer >= sd.hunt_timeout:
		_cleanup(sd)
		return FAILURE

	# 目标有效性检查
	if not sd._is_huntable_ghost_valid(sd._current_target_ghost):
		_cleanup(sd)
		return FAILURE

	var ghost: Node2D = sd._current_target_ghost as Node2D
	if ghost == null:
		_cleanup(sd)
		return FAILURE

	var dist: float = sd.global_position.distance_to(ghost.global_position)

	# 到达吞食距离：地面态只考虑水平距离（SD 只能水平移动，WG 飘在空中）
	var reach_dist: float = dist
	if not sd._is_floating_invisible:
		reach_dist = absf(sd.global_position.x - ghost.global_position.x)
	if reach_dist <= HUNT_REACH_DIST:
		return _do_hunt_success(sd)

	# 移动朝向目标
	var dir: Vector2 = (ghost.global_position - sd.global_position).normalized()

	if sd._is_floating_invisible:
		# 漂浮态：8 向移动
		sd.velocity = dir * sd.float_move_speed
		sd.anim_play(&"normal/float_move", true)
	else:
		# 地面态：只水平移动（含面向死区防抖）
		var h_dx: float = ghost.global_position.x - sd.global_position.x
		if absf(h_dx) <= sd.FACE_DEAD_ZONE:
			sd.velocity.x = 0.0
		else:
			var h_dir: float = sign(h_dx)
			sd.velocity.x = h_dir * sd.ground_run_speed
		sd.face_toward_position(ghost.global_position.x)
		# 远距离用 run，近距离切 huntting（地面态用水平距离）
		if reach_dist > HUNT_TRANSITION_DIST:
			sd.anim_play(&"normal/run", true)
		else:
			sd.anim_play(&"normal/huntting", true)

	sd.move_and_slide()
	return RUNNING


func _play_hunt_anim(sd: SoulDevourer) -> void:
	if sd._is_floating_invisible:
		sd.anim_play(&"normal/float_move", true)
	else:
		sd.anim_play(&"normal/huntting", true)


func _do_hunt_success(sd: SoulDevourer) -> int:
	# 通知幽灵被猎杀
	if sd._current_target_ghost != null and is_instance_valid(sd._current_target_ghost):
		if sd._current_target_ghost.has_method("start_being_hunted"):
			sd._current_target_ghost.call("start_being_hunted")
	sd._current_target_ghost = null

	sd.velocity.x = 0.0
	# 播放猎杀成功动画
	sd.anim_play(&"normal/huntting_succeed", false)
	# 等待动画完成（同帧内立即结束也 OK）
	sd._is_full = true
	return SUCCESS


func _cleanup(sd: SoulDevourer) -> void:
	sd._current_target_ghost = null
	sd.velocity.x = 0.0
	sd.anim_play(StringName(sd._get_anim_prefix() + "idle"), true)


func interrupt(actor: Node, blackboard: Blackboard) -> void:
	var sd: SoulDevourer = actor as SoulDevourer
	if sd != null:
		_cleanup(sd)
	super(actor, blackboard)
