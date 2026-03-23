extends ActionLeaf
class_name ActSoulDevourerLightBeamAttack

## =============================================================================
## act_light_beam_attack — 光炮攻击（P8，full 状态）
## =============================================================================
## CD 未就绪 → idle 等待（面向玩家）
## CD 就绪但仍在 hurt 锁期间 → 等 hurt 结束后再起手
## 真正起手后播放 normal/light_beam → atk_hit_on/off 事件驱动判定
## → animation_completed → _is_full = false → 进入 CD
## =============================================================================

const COOLDOWN_KEY: StringName = &"sd_light_beam_cd_end"

enum Phase { WAIT_CD, WAIT_HURT_CLEAR, FIRING }

var _phase: int = Phase.WAIT_CD


func before_run(actor: Node, blackboard: Blackboard) -> void:
	var sd: SoulDevourer = actor as SoulDevourer
	if sd == null:
		return
	sd.velocity.x = 0.0

	# 检查 CD 是否已就绪
	var actor_id: String = str(sd.get_instance_id())
	var cd_end: float = blackboard.get_value(COOLDOWN_KEY, 0.0, actor_id)
	if SoulDevourer.now_sec() >= cd_end:
		if _try_start_beam(sd):
			_phase = Phase.FIRING
		else:
			_phase = Phase.WAIT_HURT_CLEAR
	else:
		_phase = Phase.WAIT_CD
		# CD 等待期间播放 idle 动画（面向玩家）
		var player: Node2D = sd.get_priority_attack_target()
		if player != null:
			sd.face_toward_position(player.global_position.x)
		sd.anim_play(&"normal/idle", true)
		print("[SD:P8] before_run: WAIT_CD (%.1fs left)" % (cd_end - SoulDevourer.now_sec()))


func tick(actor: Node, blackboard: Blackboard) -> int:
	var sd: SoulDevourer = actor as SoulDevourer
	if sd == null:
		return FAILURE

	match _phase:
		Phase.WAIT_CD:
			return _tick_wait_cd(sd, blackboard)
		Phase.WAIT_HURT_CLEAR:
			return _tick_wait_hurt_clear(sd)
		Phase.FIRING:
			return _tick_firing(sd, blackboard)

	return RUNNING


func _tick_wait_cd(sd: SoulDevourer, blackboard: Blackboard) -> int:
	sd.velocity.x = 0.0

	# 面向玩家
	var player: Node2D = sd.get_priority_attack_target()
	if player != null:
		sd.face_toward_position(player.global_position.x)

	# 检查 CD
	var actor_id: String = str(sd.get_instance_id())
	var cd_end: float = blackboard.get_value(COOLDOWN_KEY, 0.0, actor_id)
	if SoulDevourer.now_sec() >= cd_end:
		if _try_start_beam(sd):
			_phase = Phase.FIRING
		else:
			_phase = Phase.WAIT_HURT_CLEAR
	return RUNNING


func _try_start_beam(sd: SoulDevourer) -> bool:
	if not sd.anim_play(&"normal/light_beam", false):
		print("[SD:P8] FIRE BLOCKED by hurt: current=%s, hurt_timer=%.2f" % [
			sd._current_anim, sd._hurt_timer])
		return false
	print("[SD:P8] FIRING: light_beam, full=%s" % sd._is_full)
	sd.velocity.x = 0.0
	var player: Node2D = sd.get_priority_attack_target()
	if player != null:
		sd.face_toward_position(player.global_position.x)
	return true


func _tick_wait_hurt_clear(sd: SoulDevourer) -> int:
	sd.velocity.x = 0.0
	var player: Node2D = sd.get_priority_attack_target()
	if player != null:
		sd.face_toward_position(player.global_position.x)
	if _try_start_beam(sd):
		_phase = Phase.FIRING
	return RUNNING


func _tick_firing(sd: SoulDevourer, blackboard: Blackboard) -> int:
	if sd.anim_is_finished(&"normal/light_beam"):
		sd._is_full = false
		var actor_id: String = str(sd.get_instance_id())
		blackboard.set_value(COOLDOWN_KEY, SoulDevourer.now_sec() + sd.skill_cooldown_light_beam, actor_id)
		sd._set_light_beam_hitbox_enabled(false)
		print("[SD:P8] BEAM DONE → full=false, CD=%.1fs" % sd.skill_cooldown_light_beam)
		return SUCCESS
	return RUNNING


func interrupt(actor: Node, blackboard: Blackboard) -> void:
	var sd: SoulDevourer = actor as SoulDevourer
	if sd != null:
		sd._set_light_beam_hitbox_enabled(false)
		sd.velocity.x = 0.0
	_phase = Phase.WAIT_CD
	super(actor, blackboard)
