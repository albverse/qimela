extends ActionLeaf
class_name ActSEBFlipAndStruggle

## 石眼虫弹翻流程（新规则）：
## nomal_to_flip（一次）→ struggle_loop（等待恢复触发）→ flip_to_nomal → idle。
## 恢复触发条件：
## 1) FLIPPED 下被攻击一次（触发 flipped_recover_requested）
## 2) FLIPPED 持续 5s 未被攻击（自动恢复）
##
## 说明：
## - 旧流程（被攻击后 escape_split 分裂）已废弃。
## - 旧动画名 "flip" 已废弃（deprecated），改用 "nomal_to_flip"。

const FLIPPED_TIMEOUT_MS: int = 5000

enum Phase { ENTER_FLIP, STRUGGLE, RECOVER, DONE }

var _phase: int = Phase.ENTER_FLIP


func before_run(actor: Node, _blackboard: Blackboard) -> void:
	var seb := actor as StoneEyeBug
	if seb == null:
		return

	# Reactive 重入保护：若已在挣扎阶段，不重播入场动画。
	if seb.soft_hitbox_active:
		_phase = Phase.STRUGGLE
		seb.velocity = Vector2.ZERO
		if not seb.anim_is_playing(&"struggle_loop"):
			seb.anim_play(&"struggle_loop", true, true)
		return

	_phase = Phase.ENTER_FLIP
	seb.soft_hitbox_active = false
	seb.ev_flip_done = false
	seb.velocity = Vector2.ZERO
	seb.was_attacked_while_flipped = false
	seb.flipped_recover_requested = false
	if seb.flipped_started_ms <= 0:
		seb.flipped_started_ms = StoneEyeBug.now_ms()
	seb.anim_play(&"nomal_to_flip", false, false)


func tick(actor: Node, _blackboard: Blackboard) -> int:
	var seb := actor as StoneEyeBug
	if seb == null:
		return FAILURE

	match _phase:
		Phase.ENTER_FLIP:
			return _tick_enter_flip(seb)
		Phase.STRUGGLE:
			return _tick_struggle(seb)
		Phase.RECOVER:
			return _tick_recover(seb)
		Phase.DONE:
			return SUCCESS
	return RUNNING


func _tick_enter_flip(seb: StoneEyeBug) -> int:
	if seb.ev_flip_done or seb.anim_is_finished(&"nomal_to_flip"):
		seb.ev_flip_done = false
		seb.soft_hitbox_active = true
		_phase = Phase.STRUGGLE
		seb.anim_play(&"struggle_loop", true, true)
	return RUNNING


func _tick_struggle(seb: StoneEyeBug) -> int:
	seb.velocity = Vector2.ZERO
	if not seb.anim_is_playing(&"struggle_loop"):
		seb.anim_play(&"struggle_loop", true, true)

	var elapsed_ms: int = StoneEyeBug.now_ms() - seb.flipped_started_ms
	if seb.flipped_recover_requested or elapsed_ms >= FLIPPED_TIMEOUT_MS:
		seb.soft_hitbox_active = false
		phase_to_recover(seb)
	return RUNNING


func phase_to_recover(seb: StoneEyeBug) -> void:
	_phase = Phase.RECOVER
	seb.anim_play(&"flip_to_nomal", false, true)


func _tick_recover(seb: StoneEyeBug) -> int:
	if seb.anim_is_finished(&"flip_to_nomal"):
		seb.mode = StoneEyeBug.Mode.NORMAL
		seb.soft_hitbox_active = false
		seb.was_attacked_while_flipped = false
		seb.flipped_recover_requested = false
		seb.flipped_started_ms = 0
		# 新增规则：起身回到 idle 后，立刻进入缩壳流程。
		seb.anim_play(&"idle", true, true)
		seb.mode = StoneEyeBug.Mode.RETREATING
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
	_phase = Phase.ENTER_FLIP
	super(actor, blackboard)
