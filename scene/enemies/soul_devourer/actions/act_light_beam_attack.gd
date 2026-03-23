extends ActionLeaf
class_name ActSoulDevourerLightBeamAttack

## =============================================================================
## act_light_beam_attack — 光炮攻击（P8，full 状态）
## =============================================================================
## CD 未就绪 → idle 等待（面向玩家）
## CD 就绪 → 拉开至少 100px → 蓄力 0.5s → 发射
## 真正起手后播放 normal/light_beam → atk_hit_on/off 事件驱动判定
## → animation_completed → _is_full = false → 进入 CD
## =============================================================================

const COOLDOWN_KEY: StringName = &"sd_light_beam_cd_end"
const MIN_FIRE_DISTANCE: float = 100.0
const FACE_LOOKAHEAD: float = 100.0
const CHARGE_DURATION: float = 0.5

enum Phase { WAIT_CD, REPOSITION, CHARGING, WAIT_HURT_CLEAR, FIRING }

var _phase: int = Phase.WAIT_CD
var _charge_timer: float = 0.0


func before_run(actor: Node, blackboard: Blackboard) -> void:
	var sd: SoulDevourer = actor as SoulDevourer
	if sd == null:
		return
	sd.velocity.x = 0.0
	_charge_timer = 0.0

	# 检查 CD 是否已就绪
	var actor_id: String = str(sd.get_instance_id())
	var cd_end: float = blackboard.get_value(COOLDOWN_KEY, 0.0, actor_id)
	if SoulDevourer.now_sec() >= cd_end:
		if not _has_beam_spacing(sd):
			_phase = Phase.REPOSITION
		else:
			_phase = Phase.CHARGING
			_charge_timer = 0.0
			var player: Node2D = sd.get_priority_attack_target()
			if player != null:
				sd.face_toward_position(player.global_position.x)
			sd.anim_play(&"normal/idle", true)
			print("[SD:P8] before_run: CHARGING (%.1fs)" % CHARGE_DURATION)
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
		Phase.REPOSITION:
			return _tick_reposition(sd)
		Phase.CHARGING:
			return _tick_charging(sd)
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
		if not _has_beam_spacing(sd):
			_phase = Phase.REPOSITION
		else:
			_phase = Phase.CHARGING
			_charge_timer = 0.0
	return RUNNING


func _tick_reposition(sd: SoulDevourer) -> int:
	var player: Node2D = sd.get_priority_attack_target()
	if player == null:
		sd.velocity.x = 0.0
		sd.anim_play(&"normal/idle", true)
		return RUNNING
	var dx: float = sd.global_position.x - player.global_position.x
	if absf(dx) >= MIN_FIRE_DISTANCE:
		sd.velocity.x = 0.0
		sd.face_toward_position(player.global_position.x)
		# 拉开距离后进入蓄力阶段
		_phase = Phase.CHARGING
		_charge_timer = 0.0
		sd.anim_play(&"normal/idle", true)
		print("[SD:P8] REPOSITION→CHARGING: dist=%.1f >= %.1f" % [absf(dx), MIN_FIRE_DISTANCE])
		return RUNNING
	var away_dir: float = sign(dx)
	if is_zero_approx(away_dir):
		away_dir = -1.0 if player.global_position.x >= sd.global_position.x else 1.0
	sd.velocity.x = away_dir * sd.ground_run_speed
	sd.face_toward_position(sd.global_position.x + away_dir * FACE_LOOKAHEAD)
	sd.anim_play(&"normal/run", true)
	if Engine.get_physics_frames() % 30 == 0:
		print("[SD:P8] REPOSITION: need=%.1f dist=%.1f sd_x=%.1f player_x=%.1f vel=%.1f" % [
			MIN_FIRE_DISTANCE, absf(dx), sd.global_position.x, player.global_position.x, sd.velocity.x])
	return RUNNING


func _tick_charging(sd: SoulDevourer) -> int:
	sd.velocity.x = 0.0
	var dt: float = get_physics_process_delta_time()
	_charge_timer += dt

	# 蓄力期间面向玩家，播放 idle
	var player: Node2D = sd.get_priority_attack_target()
	if player != null:
		sd.face_toward_position(player.global_position.x)
	sd.anim_play(&"normal/idle", true)

	# 蓄力期间检查距离是否仍足够（玩家可能靠近）
	if player != null:
		var dx: float = absf(sd.global_position.x - player.global_position.x)
		if dx < MIN_FIRE_DISTANCE * 0.7:
			# 玩家靠近，重新拉开距离
			_phase = Phase.REPOSITION
			_charge_timer = 0.0
			print("[SD:P8] CHARGING→REPOSITION: player too close dist=%.1f" % dx)
			return RUNNING

	if _charge_timer >= CHARGE_DURATION:
		print("[SD:P8] CHARGE DONE (%.2fs) → FIRING" % _charge_timer)
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


func _has_beam_spacing(sd: SoulDevourer) -> bool:
	var player: Node2D = sd.get_priority_attack_target()
	if player == null:
		return true
	return absf(sd.global_position.x - player.global_position.x) >= MIN_FIRE_DISTANCE


func interrupt(actor: Node, blackboard: Blackboard) -> void:
	var sd: SoulDevourer = actor as SoulDevourer
	if sd != null:
		sd._set_light_beam_hitbox_enabled(false)
		sd.velocity.x = 0.0
	_phase = Phase.WAIT_CD
	_charge_timer = 0.0
	super(actor, blackboard)
