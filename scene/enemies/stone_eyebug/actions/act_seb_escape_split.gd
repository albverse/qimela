extends ActionLeaf
class_name ActSEBEscapeSplit

## 软体逃出分裂：escape_split 动画 → escape_spawn 事件（Fallback 350ms）→ 生成软体 → 变空壳。
## CondSEBAttackedFlipped 命中后由 BT Selector 触发此动作。
## 注意：was_attacked_while_flipped 保持 true 直到动画结束才清除，
##       使 SequenceReactive 父节点在分裂完成前不会中断此序列。

var _split_start_ms: int = 0
const ESCAPE_SPAWN_DELAY_MS: int = 350


func before_run(actor: Node, _blackboard: Blackboard) -> void:
	var seb := actor as StoneEyeBug
	if seb == null:
		return
	_split_start_ms = StoneEyeBug.now_ms()
	seb.soft_hitbox_active = false  # 分裂动画阶段关闭软腹判定
	seb.ev_escape_spawn = false
	seb.velocity = Vector2.ZERO
	seb.anim_play(&"escape_split", false, true)


func tick(actor: Node, _blackboard: Blackboard) -> int:
	var seb := actor as StoneEyeBug
	if seb == null:
		return FAILURE

	# 生成软体实例：Spine escape_spawn 事件优先；Fallback 350ms 计时
	if not seb.mollusc_spawned:
		var by_event: bool = seb.ev_escape_spawn
		var by_timer: bool = (StoneEyeBug.now_ms() - _split_start_ms) >= ESCAPE_SPAWN_DELAY_MS
		if by_event or by_timer:
			seb.ev_escape_spawn = false
			seb.spawn_mollusc_instance()
			seb.mollusc_spawned = true

	# 动画结束 → 壳变空壳
	if seb.anim_is_finished(&"escape_split"):
		seb.was_attacked_while_flipped = false  # 清除后 CondSEBAttackedFlipped 不再 SUCCESS
		seb.notify_become_empty_shell()
		seb.anim_play(&"in_shell_loop", true, true)
		return SUCCESS

	return RUNNING


func interrupt(actor: Node, blackboard: Blackboard) -> void:
	var seb := actor as StoneEyeBug
	if seb != null:
		seb.ev_escape_spawn = false
		seb.velocity = Vector2.ZERO
	super(actor, blackboard)
