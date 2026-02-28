extends ActionLeaf
class_name ActShootFace

## Act_ShootFace（发射面具攻击）
## 在 FLYING_ATTACK 模式下，has_face=true 时执行。
## 玩家在 200px 内时，飞到玩家斜上方偏移点，播放 shoot_face。
## 读到 Spine 事件 shoot 的瞬间，从 StoneMaskBird/ShootPoint 发射子弹并切换为 no_face。
## 发射后优先进入 RETURN_TO_REST。

enum Phase { HOVERING, SHOOTING }

const HOVER_CLOSE_DIST: float = 20.0
const SHOOT_TIMEOUT_SEC: float = 1.2

var _phase: int = Phase.HOVERING
var _shoot_started_sec: float = -1.0
var _bullet_spawned: bool = false


func before_run(actor: Node, _blackboard: Blackboard) -> void:
	_phase = Phase.HOVERING
	_shoot_started_sec = -1.0
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
	var dist_to_player := bird.global_position.distance_to(player.global_position)
	if dist_to_player > bird.face_shoot_range_px:
		bird.mode = StoneMaskBird.Mode.RETURN_TO_REST
		return SUCCESS

	match _phase:
		Phase.HOVERING:
			return _tick_hovering(bird, now, player)
		Phase.SHOOTING:
			return _tick_shooting(bird, now, player)

	return RUNNING


func _tick_hovering(bird: StoneMaskBird, now: float, player: Node2D) -> int:
	var hover_point := player.global_position + bird.face_hover_offset
	var to_hover := hover_point - bird.global_position
	var dist := to_hover.length()
	if dist > HOVER_CLOSE_DIST:
		bird.velocity = to_hover.normalized() * bird.hover_speed
		bird.move_and_slide()
		if not bird.anim_is_playing(&"fly_move"):
			bird.anim_play(&"fly_move", true, true)
		return RUNNING

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
	_bullet_spawned = false
	super(actor, blackboard)
