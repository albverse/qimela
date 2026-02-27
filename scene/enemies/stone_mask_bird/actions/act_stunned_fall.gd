extends ActionLeaf
class_name ActStunnedFallLoop

## 7.5 Act_StunnedFallLoop（坠落 -> 落地 -> 地面眩晕）
## 内部阶段：FALLING -> LANDING -> STUNNED_GROUND
## before_run: 播放 fall_loop(loop)，写 stun_until_sec
## tick:
##   - 未触地：维持坠落，RUNNING
##   - 触地瞬间：播放 land(once)
##   - land 播放完：切 stun_loop(loop) 直到 stun_until
##   - 到 stun_until_sec：mode=WAKE_FROM_STUN，SUCCESS

enum Phase { FALLING, LANDING, STUNNED_GROUND }

var _phase: int = Phase.FALLING

func before_run(actor: Node, _blackboard: Blackboard) -> void:
	var bird := actor as StoneMaskBird
	if bird == null:
		return
	_phase = Phase.FALLING
	bird.anim_play(&"fall_loop", true, true)
	var now := StoneMaskBird.now_sec()
	bird.stun_until_sec = now + bird.stun_duration_sec
	# 清除水平速度，保留/设置垂直下落
	bird.velocity.x = 0.0


func tick(actor: Node, _blackboard: Blackboard) -> int:
	var bird := actor as StoneMaskBird
	if bird == null:
		return FAILURE

	var dt: float = actor.get_physics_process_delta_time()
	var now := StoneMaskBird.now_sec()

	match _phase:
		Phase.FALLING:
			return _tick_falling(bird, dt)
		Phase.LANDING:
			return _tick_landing(bird, now)
		Phase.STUNNED_GROUND:
			return _tick_stunned_ground(bird, now)
	return RUNNING


func _tick_falling(bird: StoneMaskBird, dt: float) -> int:
	# 施加重力下落
	bird.velocity.y += bird.fall_gravity * dt
	bird.velocity.x = 0.0
	bird.move_and_slide()

	# 触地检测
	if bird.is_on_floor():
		_phase = Phase.LANDING
		bird.velocity = Vector2.ZERO
		bird.anim_play(&"land", false, true)
	return RUNNING


func _tick_landing(bird: StoneMaskBird, now: float) -> int:
	# 等待 land 动画播放完
	if bird.anim_is_finished(&"land"):
		_phase = Phase.STUNNED_GROUND
		bird.anim_play(&"stun_loop", true, true)
	return RUNNING


func _tick_stunned_ground(bird: StoneMaskBird, now: float) -> int:
	# 地面眩晕循环，等到 stun_until_sec
	if now >= bird.stun_until_sec:
		bird.mode = StoneMaskBird.Mode.WAKE_FROM_STUN
		return SUCCESS
	return RUNNING


func interrupt(actor: Node, blackboard: Blackboard) -> void:
	var bird := actor as StoneMaskBird
	if bird:
		bird.velocity = Vector2.ZERO
		bird.anim_stop_or_blendout()
	_phase = Phase.FALLING
	super(actor, blackboard)
