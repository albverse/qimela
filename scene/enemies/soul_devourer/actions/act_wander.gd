extends ActionLeaf
class_name ActSoulDevourerWander

## =============================================================================
## act_wander — 地面闲逛（P11）
## =============================================================================
## idle 超过 1 秒后进入。围绕当前位置随机选择目标点并用 normal/run 移动。
## 若闲逛时玩家靠近，由更高优先级的强制隐身分支接管。
## =============================================================================

const MIN_WANDER_DIST: float = 48.0
const MAX_WANDER_DIST: float = 120.0
const ARRIVE_EPSILON: float = 8.0
const RETARGET_INTERVAL: float = 1.25

var _target_x: float = 0.0
var _retarget_timer: float = 0.0


func before_run(actor: Node, _blackboard: Blackboard) -> void:
	var sd: SoulDevourer = actor as SoulDevourer
	if sd == null:
		return
	sd._is_wandering = true
	sd._idle_elapsed = 0.0
	_pick_target(sd)
	sd.anim_play(&"normal/run", true)


func tick(actor: Node, _blackboard: Blackboard) -> int:
	var sd: SoulDevourer = actor as SoulDevourer
	if sd == null:
		return FAILURE

	var dt: float = get_physics_process_delta_time()
	_retarget_timer -= dt
	if _retarget_timer <= 0.0 or absf(_target_x - sd.global_position.x) <= ARRIVE_EPSILON:
		_pick_target(sd)

	var dx: float = _target_x - sd.global_position.x
	if absf(dx) <= ARRIVE_EPSILON:
		sd.velocity.x = 0.0
		sd.anim_play(&"normal/idle", true)
	else:
		var dir: float = sign(dx)
		sd.velocity.x = dir * sd.ground_run_speed
		sd.face_toward_position(_target_x)
		sd.anim_play(&"normal/run", true)

	if Engine.get_physics_frames() % 45 == 0:
		print("[SD:P11] WANDER: target_x=%.1f sd_x=%.1f vel=%.1f" % [
			_target_x, sd.global_position.x, sd.velocity.x])
	return RUNNING


func _pick_target(sd: SoulDevourer) -> void:
	var dir: float = -1.0 if randf() < 0.5 else 1.0
	var dist: float = randf_range(MIN_WANDER_DIST, MAX_WANDER_DIST)
	_target_x = sd.global_position.x + dir * dist
	_retarget_timer = RETARGET_INTERVAL


func _cleanup(sd: SoulDevourer) -> void:
	sd.velocity.x = 0.0
	sd._is_wandering = false
	sd._idle_elapsed = 0.0


func interrupt(actor: Node, blackboard: Blackboard) -> void:
	var sd: SoulDevourer = actor as SoulDevourer
	if sd != null:
		_cleanup(sd)
	super(actor, blackboard)
