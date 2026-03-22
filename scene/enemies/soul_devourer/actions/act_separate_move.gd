extends ActionLeaf
class_name ActSoulDevourerSeparateMove

## =============================================================================
## act_separate_move — 双头犬分离后强制远离 partner（P2）
## =============================================================================
## 移动 separate_distance 后清除 _force_separate。
## =============================================================================

var _moved: float = 0.0
var _direction: float = 1.0


func before_run(actor: Node, _blackboard: Blackboard) -> void:
	_moved = 0.0
	var sd: SoulDevourer = actor as SoulDevourer
	if sd == null:
		return
	# 随机方向（或根据场景位置决定）
	_direction = 1.0 if randf() > 0.5 else -1.0
	sd.anim_play(&"normal/run", true)


func tick(actor: Node, _blackboard: Blackboard) -> int:
	var sd: SoulDevourer = actor as SoulDevourer
	if sd == null:
		return FAILURE

	if not sd._force_separate:
		return SUCCESS

	var dt: float = get_physics_process_delta_time()
	sd.velocity.x = _direction * sd.separate_speed
	sd.velocity.y += 1200.0 * dt  # 重力
	if sd.is_on_floor():
		sd.velocity.y = 0.0
	sd.move_and_slide()

	_moved += sd.separate_speed * dt
	if _moved >= sd.separate_distance:
		sd._force_separate = false
		sd.velocity.x = 0.0
		sd.anim_play(&"normal/idle", true)
		return SUCCESS

	return RUNNING


func interrupt(actor: Node, blackboard: Blackboard) -> void:
	var sd: SoulDevourer = actor as SoulDevourer
	if sd != null:
		sd.velocity.x = 0.0
	super(actor, blackboard)
