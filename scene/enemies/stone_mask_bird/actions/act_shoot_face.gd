extends ActionLeaf
class_name ActShootFace

## Act_ShootFace（发射面具攻击）
## 在 FLYING_ATTACK 模式下，has_face=true 时执行。
## 播放 shoot_face 动画，等待 Spine 事件 "shoot" 触发面具脱落。
##
## 内部阶段：HOVERING -> SHOOTING -> DONE
## - HOVERING：飞到玩家上方悬停点
## - SHOOTING：播放 shoot_face 动画，等待 shoot 事件
##   shoot 事件触发时：has_face=false（面具脱落）
## - 动画结束后 SUCCESS，BT 自然切换到其他分支（无面具的普通攻击/追击）
##
## shoot 事件由 StoneMaskBird._on_spine_animation_event() 写入 face_shoot_event_fired。
## 无 Spine 时由兜底超时触发（fallback duration 0.6s 后 anim_is_finished 为 true）。

enum Phase { HOVERING, SHOOTING }

const HOVER_CLOSE_DIST: float = 20.0
const SHOOT_TIMEOUT_SEC: float = 1.0

var _phase: int = Phase.HOVERING
var _shoot_started_sec: float = -1.0


func before_run(actor: Node, _blackboard: Blackboard) -> void:
	_phase = Phase.HOVERING
	_shoot_started_sec = -1.0
	var bird := actor as StoneMaskBird
	if bird:
		bird.face_shoot_event_fired = false


func tick(actor: Node, _blackboard: Blackboard) -> int:
	var bird := actor as StoneMaskBird
	if bird == null:
		return FAILURE

	# has_face 在 shoot 事件回调中被清除后，动画仍需播完
	var now := StoneMaskBird.now_sec()
	var player := bird._get_player()

	match _phase:
		Phase.HOVERING:
			return _tick_hovering(bird, now, player)
		Phase.SHOOTING:
			return _tick_shooting(bird, now)

	return RUNNING


func _tick_hovering(bird: StoneMaskBird, now: float, player: Node2D) -> int:
	# 飞到玩家上方悬停点
	if player:
		var hover_point := player.global_position + Vector2(0, -bird.attack_offset_y)
		var to_hover := hover_point - bird.global_position
		var dist := to_hover.length()
		if dist > HOVER_CLOSE_DIST:
			bird.velocity = to_hover.normalized() * bird.hover_speed
			bird.move_and_slide()
			if not bird.anim_is_playing(&"fly_move"):
				bird.anim_play(&"fly_move", true, true)
			return RUNNING

	# 到达悬停点或无玩家 → 开始发射
	bird.velocity = Vector2.ZERO
	bird.face_shoot_event_fired = false
	_phase = Phase.SHOOTING
	_shoot_started_sec = now
	bird.anim_play(&"shoot_face", false, false)
	return RUNNING


func _tick_shooting(bird: StoneMaskBird, now: float) -> int:
	# 检测 shoot 事件是否已触发（由 Spine event 或 Mock 兜底）
	if bird.face_shoot_event_fired and bird.has_face:
		bird.has_face = false

	# Mock 兜底：无 Spine 时，动画到一半时模拟 shoot 事件
	if not bird.face_shoot_event_fired and bird._anim_mock != null:
		if _shoot_started_sec > 0.0 and now - _shoot_started_sec >= 0.3:
			bird.face_shoot_event_fired = true
			bird.has_face = false

	# 动画结束或超时 → 完成
	if bird.anim_is_finished(&"shoot_face") or (_shoot_started_sec > 0.0 and now - _shoot_started_sec >= SHOOT_TIMEOUT_SEC):
		# 确保面具已脱落（兜底，防止 shoot 事件未触发）
		if bird.has_face:
			bird.has_face = false
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
	super(actor, blackboard)
