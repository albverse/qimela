extends ActionLeaf
class_name ActMolluscSpawnEnter

## Mollusc 生成入场：播放 enter，期间冻结位移；结束后解锁常规 BT 分支。

const ENTER_TIMEOUT_SEC: float = 1.0
var _started_ms: int = 0

func before_run(actor: Node, _blackboard: Blackboard) -> void:
	var mollusc := actor as Mollusc
	if mollusc == null:
		return
	mollusc.velocity = Vector2.ZERO
	_started_ms = Time.get_ticks_msec()
	if not mollusc.anim_is_playing(&"enter") and not mollusc.anim_is_finished(&"enter"):
		mollusc.anim_play(&"enter", false, false)


func tick(actor: Node, _blackboard: Blackboard) -> int:
	var mollusc := actor as Mollusc
	if mollusc == null:
		return FAILURE
	mollusc.velocity = Vector2.ZERO
	if mollusc.anim_is_finished(&"enter"):
		mollusc.finish_spawn_enter()
		return SUCCESS
	if _started_ms > 0 and float(Time.get_ticks_msec() - _started_ms) / 1000.0 >= ENTER_TIMEOUT_SEC:
		# 兜底：资源缺失/事件异常时，避免卡在入场分支。
		mollusc.finish_spawn_enter()
		return SUCCESS
	if not mollusc.anim_is_playing(&"enter"):
		mollusc.anim_play(&"enter", false, false)
	return RUNNING


func interrupt(actor: Node, blackboard: Blackboard) -> void:
	var mollusc := actor as Mollusc
	if mollusc != null:
		mollusc.velocity = Vector2.ZERO
	super(actor, blackboard)
