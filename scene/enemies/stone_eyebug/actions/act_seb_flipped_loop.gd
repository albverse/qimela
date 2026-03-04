extends ActionLeaf
class_name ActSEBFlippedLoop

## 石眼虫弹翻流程：flip → struggle_loop → （被攻击后）escape_split → 生成软体 → 空壳。
## 弹翻阶段冻结移动，软体易伤盒开启。

enum Phase { FLIP, STRUGGLE, ESCAPE_SPLIT, DONE }

var _phase: int = Phase.FLIP
## escape_split 开始的时间戳（ms），用于模拟 escape_spawn 帧（0.35s 后）
var _split_start_ms: int = 0
const ESCAPE_SPAWN_DELAY_MS: int = 350


func before_run(actor: Node, _blackboard: Blackboard) -> void:
	var seb := actor as StoneEyeBug
	if seb == null:
		return
	_phase = Phase.FLIP
	seb.was_attacked_while_flipped = false
	seb.soft_hitbox_active = false
	seb.mollusc_spawned = false
	# 冻结水平速度
	seb.velocity = Vector2.ZERO
	seb.anim_play(&"flip", false, false)


func tick(actor: Node, _blackboard: Blackboard) -> int:
	var seb := actor as StoneEyeBug
	if seb == null:
		return FAILURE

	match _phase:
		Phase.FLIP:
			return _tick_flip(seb)
		Phase.STRUGGLE:
			return _tick_struggle(seb)
		Phase.ESCAPE_SPLIT:
			return _tick_escape_split(seb)
		Phase.DONE:
			return SUCCESS
	return RUNNING


func _tick_flip(seb: StoneEyeBug) -> int:
	if seb.anim_is_finished(&"flip"):
		_phase = Phase.STRUGGLE
		seb.anim_play(&"struggle_loop", true, true)
		seb.soft_hitbox_active = true
	return RUNNING


func _tick_struggle(seb: StoneEyeBug) -> int:
	# 等待被攻击触发分裂
	if seb.was_attacked_while_flipped:
		_phase = Phase.ESCAPE_SPLIT
		_split_start_ms = StoneEyeBug.now_ms()
		seb.soft_hitbox_active = false
		seb.was_attacked_while_flipped = false
		seb.anim_play(&"escape_split", false, true)
	return RUNNING


func _tick_escape_split(seb: StoneEyeBug) -> int:
	# 在 escape_spawn 帧（0.35s 后）生成软体实例
	if not seb.mollusc_spawned:
		var elapsed_ms := StoneEyeBug.now_ms() - _split_start_ms
		if elapsed_ms >= ESCAPE_SPAWN_DELAY_MS:
			seb.spawn_mollusc_instance()
			seb.mollusc_spawned = true

	# escape_split 动画结束 → 壳变为空壳
	if seb.anim_is_finished(&"escape_split"):
		seb.notify_become_empty_shell()
		seb.anim_play(&"in_shell_loop", true, true)
		_phase = Phase.DONE
		return SUCCESS

	return RUNNING


func interrupt(actor: Node, blackboard: Blackboard) -> void:
	var seb := actor as StoneEyeBug
	if seb != null:
		seb.soft_hitbox_active = false
		seb.velocity = Vector2.ZERO
		seb.force_close_hit_windows()  # 安全关窗
	_phase = Phase.FLIP
	super(actor, blackboard)
