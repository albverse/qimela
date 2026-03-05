extends ActionLeaf
class_name ActSEBFlipAndStruggle

## 石眼虫弹翻流程（新规则）：
## nomal_to_flip（一次）→ struggle_loop（等待恢复/分裂触发）
## - 若被 ghost_fist / chimera_ghost_hand_l / stone_mask_bird_face_bullet 命中一次或 5s 超时：flip_to_nomal → idle → RETREATING
## - 若被其它武器命中 SoftHurtbox 超过 3 次：escape_split（不可打断）→ empty_loop + EMPTY_SHELL

const FLIPPED_TIMEOUT_MS: int = 5000

enum Phase { ENTER_FLIP, STRUGGLE, ESCAPE_SPLIT, RECOVER, DONE }

var _phase: int = Phase.ENTER_FLIP


func before_run(actor: Node, _blackboard: Blackboard) -> void:
	var seb := actor as StoneEyeBug
	if seb == null:
		return

	# Reactive 重入保护：若已在挣扎阶段，不重播入场动画。
	if seb.soft_hitbox_active and seb.mode == StoneEyeBug.Mode.FLIPPED:
		_phase = Phase.STRUGGLE
		seb.velocity = Vector2.ZERO
		if not seb.anim_is_playing(&"struggle_loop"):
			seb.anim_play(&"struggle_loop", true, true)
		return

	_phase = Phase.ENTER_FLIP
	seb.soft_hitbox_active = false
	seb.ev_flip_done = false
	seb.ev_escape_spawn = false
	seb.velocity = Vector2.ZERO
	seb.was_attacked_while_flipped = false
	seb.flipped_recover_requested = false
	seb.flipped_escape_hit_count = 0
	seb.flipped_escape_requested = false
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
		Phase.ESCAPE_SPLIT:
			return _tick_escape_split(seb)
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

	if seb.flipped_escape_requested:
		seb.soft_hitbox_active = false
		_phase = Phase.ESCAPE_SPLIT
		seb.ev_escape_spawn = false
		seb.anim_play(&"escape_split", false, false)
		return RUNNING

	var elapsed_ms: int = StoneEyeBug.now_ms() - seb.flipped_started_ms
	if seb.flipped_recover_requested or elapsed_ms >= FLIPPED_TIMEOUT_MS:
		seb.soft_hitbox_active = false
		_phase = Phase.RECOVER
		seb.anim_play(&"flip_to_nomal", false, true)
	return RUNNING


func _tick_escape_split(seb: StoneEyeBug) -> int:
	if seb.ev_escape_spawn and not seb.mollusc_spawned:
		seb.ev_escape_spawn = false
		seb.spawn_mollusc_instance()
		seb.mollusc_spawned = true

	if seb.anim_is_finished(&"escape_split"):
		if not seb.mollusc_spawned:
			# fallback：若资源缺事件，动画结束时兜底生成一次
			seb.spawn_mollusc_instance()
			seb.mollusc_spawned = true
		seb.notify_become_empty_shell()
		seb.anim_play(&"empty_loop", true, true)
		_phase = Phase.DONE
		return SUCCESS
	return RUNNING


func _tick_recover(seb: StoneEyeBug) -> int:
	if seb.anim_is_finished(&"flip_to_nomal"):
		seb.mode = StoneEyeBug.Mode.NORMAL
		seb.soft_hitbox_active = false
		seb.was_attacked_while_flipped = false
		seb.flipped_recover_requested = false
		seb.flipped_escape_requested = false
		seb.flipped_escape_hit_count = 0
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
		# escape_split 播放期间不可打断
		if _phase == Phase.ESCAPE_SPLIT and not seb.anim_is_finished(&"escape_split"):
			return
		seb.soft_hitbox_active = false
		seb.velocity = Vector2.ZERO
		seb.ev_flip_done = false
		seb.force_close_hit_windows()
	_phase = Phase.ENTER_FLIP
	super(actor, blackboard)
