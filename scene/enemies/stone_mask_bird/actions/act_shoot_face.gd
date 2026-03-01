extends ActionLeaf
class_name ActShootFace

## Act_ShootFace（发射面具攻击）
## 在 FLYING_ATTACK 模式下，has_face=true 时由 BT 触发。
##
## 执行流程：
##   1. HOVERING：fly_move 飞向玩家偏移悬停点（约 200px 外），不因玩家离开范围而中止。
##   2. SHOOTING：播放 shoot_face 动画，Spine 事件 shoot 触发时发射子弹并切 no_face，
##               等待动画完整结束后才退出。
##
## 承诺机制：before_run() 调用时即将 shoot_face_committed 置 true，
##   此后 CondHasFace / CondPlayerInFaceShootRange 在 committed=true 期间始终返回 SUCCESS，
##   使 Seq_ShootFace 不会因"has_face=false"或"玩家离开范围"而 BT 中断此动作。
##   只有眩晕 / weak（更高优先级序列）才能真正打断。
## 发射完成后立即设置 RETURN_TO_REST，committed 同步清零。

enum Phase { HOVERING, SHOOTING }

const HOVER_CLOSE_DIST: float = 20.0
const HOVER_TIMEOUT_SEC: float = 2.5
const HOVER_STALL_TIMEOUT_SEC: float = 0.8

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
		bird.shoot_face_committed = true  # 锁定：BT 条件节点在此期间始终通过


func tick(actor: Node, _blackboard: Blackboard) -> int:
	var bird := actor as StoneMaskBird
	if bird == null:
		return FAILURE

	var now := StoneMaskBird.now_sec()

	match _phase:
		Phase.HOVERING:
			var player := bird._get_player()
			if player == null:
				# 目标消失，无法计算悬停位置，中止并回巢
				_clear_committed(bird)
				bird.mode = StoneMaskBird.Mode.RETURN_TO_REST
				return SUCCESS
			return _tick_hovering(bird, now, player)

		Phase.SHOOTING:
			# SHOOTING 阶段不再依赖玩家范围，子弹在事件触发时已锁定目标
			var player := bird._get_player()
			return _tick_shooting(bird, now, player)

	return RUNNING


func _clear_committed(bird: StoneMaskBird) -> void:
	if bird:
		bird.shoot_face_committed = false


func _compute_hover_point(bird: StoneMaskBird, player: Node2D) -> Vector2:
	# 悬停点：沿 player→bird 轴线方向，距玩家 face_shoot_hover_dist px 处。
	# 若鸟与玩家重叠（极端情况），退化为正上方。
	var dir := (bird.global_position - player.global_position).normalized()
	if dir == Vector2.ZERO:
		dir = Vector2.UP
	return player.global_position + dir * bird.face_shoot_hover_dist

func _tick_hovering(bird: StoneMaskBird, now: float, player: Node2D) -> int:
	if _hover_started_sec < 0.0:
		_hover_started_sec = now
		_last_hover_dist = INF
		_hover_stall_sec = 0.0

	# 每帧重新根据玩家当前位置计算悬停点，追踪移动中的玩家
	var hover_point: Vector2 = _compute_hover_point(bird, player)
	var to_hover: Vector2 = hover_point - bird.global_position
	var dist: float = to_hover.length()
	var dt := bird.get_physics_process_delta_time()

	# 检测停滞（目标持续无法靠近）
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
		print("[StoneMaskBird][ShootFace][WARN] hover fallback: dist=%.2f elapsed=%.2f stall=%.2f hover_dist=%.1f" % [
			dist,
			now - _hover_started_sec,
			_hover_stall_sec,
			bird.face_shoot_hover_dist,
		])

	# 到达悬停点（或超时兜底）→ 进入 SHOOTING
	bird.velocity = Vector2.ZERO
	bird.face_shoot_event_fired = false
	_phase = Phase.SHOOTING
	_shoot_started_sec = now
	bird.anim_play(&"shoot_face", false, false)
	return RUNNING


func _tick_shooting(bird: StoneMaskBird, now: float, player: Node2D) -> int:
	# Spine 事件触发发射
	if bird.face_shoot_event_fired and not _bullet_spawned:
		bird.spawn_face_bullet(player)
		_bullet_spawned = true
		bird.has_face = false

	# Mock 驱动兜底（无 Spine 时按时间模拟事件）
	if not bird.face_shoot_event_fired and bird._anim_mock != null:
		if _shoot_started_sec > 0.0 and now - _shoot_started_sec >= 0.5 and not _bullet_spawned:
			bird.face_shoot_event_fired = true
			bird.spawn_face_bullet(player)
			_bullet_spawned = true
			bird.has_face = false

	# 等待 shoot_face 动画完整播完再离开（不因 has_face=false 提前退出）
	if bird.anim_is_finished(&"shoot_face"):
		_clear_committed(bird)
		bird.mode = StoneMaskBird.Mode.RETURN_TO_REST
		bird.next_attack_sec = now + bird.dash_cooldown
		return SUCCESS

	return RUNNING


func interrupt(actor: Node, blackboard: Blackboard) -> void:
	var bird := actor as StoneMaskBird
	if bird:
		bird.velocity = Vector2.ZERO
		bird.face_shoot_event_fired = false
		_clear_committed(bird)
	_phase = Phase.HOVERING
	_shoot_started_sec = -1.0
	_hover_started_sec = -1.0
	_last_hover_dist = INF
	_hover_stall_sec = 0.0
	_bullet_spawned = false
	super(actor, blackboard)
