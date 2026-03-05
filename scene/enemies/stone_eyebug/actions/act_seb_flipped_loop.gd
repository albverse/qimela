extends ActionLeaf
class_name ActSEBFlipAndStruggle

## 石眼虫弹翻入场：flip 动画 → 开启软腹伤害盒 → 播 struggle_loop → 返回 SUCCESS。
## 后续挣扎/逃跑分裂逻辑由 BT 内层 Selector 负责：
##   InnerSelector:
##     Seq_EscapeSplit: [CondSEBAttackedFlipped] → [ActSEBEscapeSplit]
##     ActSEBStruggleIdle (RUNNING 兜底)
##
## Spine flip_done 事件优先；Fallback：轮询 anim_is_finished("flip")。

enum Phase { FLIP, DONE }

var _phase: int = Phase.FLIP


func before_run(actor: Node, _blackboard: Blackboard) -> void:
	var seb := actor as StoneEyeBug
	if seb == null:
		return
	# 根因修复：Root 使用 SequenceReactive，会反复重入 before_run。
	# 仅在首次进入 FLIPPED 时播放 flip，后续重入保持 struggle_loop。
	if seb.flipped_intro_done:
		_phase = Phase.DONE
		seb.soft_hitbox_active = true
		seb.velocity = Vector2.ZERO
		if not seb.anim_is_playing(&"struggle_loop"):
			seb.anim_play(&"struggle_loop", true, true)
		return
	_phase = Phase.FLIP
	seb.was_attacked_while_flipped = false
	seb.soft_hitbox_active = false
	seb.mollusc_spawned = false
	seb.ev_flip_done = false
	seb.velocity = Vector2.ZERO
	seb.anim_play(&"flip", false, false)


func tick(actor: Node, _blackboard: Blackboard) -> int:
	var seb := actor as StoneEyeBug
	if seb == null:
		return FAILURE

	if _phase == Phase.DONE:
		return SUCCESS

	# 优先 Spine flip_done 事件；Fallback 轮询动画结束
	if seb.ev_flip_done or seb.anim_is_finished(&"flip"):
		seb.ev_flip_done = false
		seb.soft_hitbox_active = true
		seb.flipped_intro_done = true
		seb.anim_play(&"struggle_loop", true, true)
		_phase = Phase.DONE
		return SUCCESS

	return RUNNING


func interrupt(actor: Node, blackboard: Blackboard) -> void:
	var seb := actor as StoneEyeBug
	if seb != null:
		seb.soft_hitbox_active = false
		seb.velocity = Vector2.ZERO
		seb.ev_flip_done = false
		seb.force_close_hit_windows()
	_phase = Phase.FLIP
	super(actor, blackboard)
