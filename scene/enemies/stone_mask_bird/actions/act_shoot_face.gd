extends ActionLeaf
class_name ActShootFace

## Act_ShootFace（发射面具攻击）
## 在 FLYING_ATTACK 模式下，has_face=true 时执行。
## 玩家在 face_shoot_range_px 内时，飞到玩家斜上方偏移点，播放 shoot_face。
## 读到 Spine 事件 shoot 的瞬间，从 StoneMaskBird/ShootPoint 发射子弹并切换为 no_face。
## 发射后优先进入 RETURN_TO_REST。

enum Phase { HOVERING, SHOOTING }

const HOVER_CLOSE_DIST: float = 20.0
const HOVER_TIMEOUT_SEC: float = 2.5
const HOVER_STALL_TIMEOUT_SEC: float = 0.8
const SHOOT_TIMEOUT_SEC: float = 1.2

var _phase: int = Phase.HOVERING
var _shoot_started_sec: float = -1.0
var _hover_started_sec: float = -1.0
var _last_hover_dist: float = INF
var _hover_stall_sec: float = 0.0
var _bullet_spawned: bool = false


func before_run(actor: Node, _blackboard: Blackboard) -> void:
	_phase = Phase.HOVERING
	_shoot_started_sec = -1.0
	_hover_started_sec = -1.0
	_last_hover_dist = INF
	_hover_stall_sec = 0.0
	_bullet_spawned = false
	var bird := actor as StoneMaskBird
	if bird:
		bird.face_shoot_event_fired = false


func tick(actor: Node, _blackboard: Blackboard) -> int:
	var bird := actor as StoneMaskBird
	if bird == null:
		return FAILURE

	if not bird.has_face:
		bird.mode = StoneMaskBird.Mode.RETURN_TO_REST
		return SUCCESS

	var player := bird._get_player()
	if player == null:
		bird.mode = StoneMaskBird.Mode.RETURN_TO_REST
		return SUCCESS

	var now := StoneMaskBird.now_sec()

	match _phase:
		Phase.HOVERING:
			var dist_to_player := bird.global_position.distance_to(player.global_position)
			if dist_to_player > bird.face_shoot_engage_range_px():
				bird.mode = StoneMaskBird.Mode.RETURN_TO_REST
				return SUCCESS
			return _tick_hovering(bird, now, player)
		Phase.SHOOTING:
			# 进入 SHOOTING 后不再做距离退出检查，保证起手后动作完整执行。
			return _tick_shooting(bird, now, player)

	return RUNNING


func _tick_hovering(bird: StoneMaskBird, now: float, player: Node2D) -> int:
	if _hover_started_sec < 0.0:
		_hover_started_sec = now
		_last_hover_dist = INF
		_hover_stall_sec = 0.0

	var hover_point: Vector2 = player.global_position + bird.face_hover_offset
	var to_hover: Vector2 = hover_point - bird.global_position
	var dist: float = to_hover.length()
	var dt := bird.get_physics_process_delta_time()

	# 若偏移点因障碍/移动目标导致长期无法到达，则兜底进入 SHOOTING，避免永远 RUNNING。
	if dist < _last_hover_dist - 1.0:
		_hover_stall_sec = 0.0
	else:
		_hover_stall_sec += dt
	_last_hover_dist = dist

	if dist > HOVER_CLOSE_DIST and (now - _hover_started_sec) < HOVER_TIMEOUT_SEC and _hover_stall_sec < HOVER_STALL_TIMEOUT_SEC:
		bird.velocity = to_hover.normalized() * bird.hover_speed
		bird.move_and_slide()
		if not bird.anim_is_playing(&"fly_move"):
			bird.anim_play(&"fly_move", true, true)
		return RUNNING

	if dist > HOVER_CLOSE_DIST and ((now - _hover_started_sec) >= HOVER_TIMEOUT_SEC or _hover_stall_sec >= HOVER_STALL_TIMEOUT_SEC):
		print("[StoneMaskBird][ShootFace][WARN] hover fallback: dist=%.2f elapsed=%.2f stall=%.2f offset=%s" % [
			dist,
			now - _hover_started_sec,
			_hover_stall_sec,
			str(bird.face_hover_offset),
		])

	bird.velocity = Vector2.ZERO
	bird.face_shoot_event_fired = false
	_phase = Phase.SHOOTING
	_shoot_started_sec = now
	bird.anim_play(&"shoot_face", false, false)
	return RUNNING


func _tick_shooting(bird: StoneMaskBird, now: float, player: Node2D) -> int:
	if bird.face_shoot_event_fired and not _bullet_spawned:
		bird.spawn_face_bullet(player)
		_bullet_spawned = true
		bird.has_face = false

	if not bird.face_shoot_event_fired and bird._anim_mock != null:
		if _shoot_started_sec > 0.0 and now - _shoot_started_sec >= 0.5 and not _bullet_spawned:
			bird.face_shoot_event_fired = true
			bird.spawn_face_bullet(player)
			_bullet_spawned = true
			bird.has_face = false

	if bird.anim_is_finished(&"shoot_face") or (_shoot_started_sec > 0.0 and now - _shoot_started_sec >= SHOOT_TIMEOUT_SEC):
		bird.mode = StoneMaskBird.Mode.RETURN_TO_REST
		bird.next_attack_sec = now + bird.dash_cooldown
		return SUCCESS

	return RUNNING


func interrupt(actor: Node, blackboard: Blackboard) -> void:
	var bird := actor as StoneMaskBird
	if bird:
		bird.velocity = Vector2.ZERO
		bird.anim_stop_or_blendout()
		bird.face_shoot_event_fired = false
	_phase = Phase.HOVERING
	_shoot_started_sec = -1.0
	_hover_started_sec = -1.0
	_last_hover_dist = INF
	_hover_stall_sec = 0.0
	_bullet_spawned = false
	super(actor, blackboard)
