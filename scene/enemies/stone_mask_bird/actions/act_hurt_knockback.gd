extends ActionLeaf
class_name ActHurtKnockbackFlicker

## 7.4 Act_HurtKnockbackFlicker（0.2s / 40px）
## 飞行受击：播放 hurt 动画，执行击退与闪烁，完成后返回 FLYING_ATTACK。

var _knockback_dir: Vector2 = Vector2.ZERO

func before_run(actor: Node, _blackboard: Blackboard) -> void:
	var bird := actor as StoneMaskBird
	if bird == null:
		return
	bird.anim_play(&"hurt", false, true)
	var now := StoneMaskBird.now_sec()
	bird.hurt_until_sec = now + bird.hurt_duration
	# 计算击退方向（远离玩家）
	var player := bird._get_player()
	if player:
		_knockback_dir = (bird.global_position - player.global_position).normalized()
	else:
		_knockback_dir = Vector2.UP


func tick(actor: Node, _blackboard: Blackboard) -> int:
	var bird := actor as StoneMaskBird
	if bird == null:
		return FAILURE
	var now := StoneMaskBird.now_sec()
	if now < bird.hurt_until_sec:
		# 还在受击中：执行击退
		var dt := actor.get_physics_process_delta_time()
		var knockback_speed: float = bird.hurt_knockback_px / bird.hurt_duration
		bird.velocity = _knockback_dir * knockback_speed
		bird.move_and_slide()
		return RUNNING
	# 受击结束 -> 返回飞行攻击
	bird.velocity = Vector2.ZERO
	bird.mode = StoneMaskBird.Mode.FLYING_ATTACK
	return SUCCESS


func interrupt(actor: Node, blackboard: Blackboard) -> void:
	var bird := actor as StoneMaskBird
	if bird:
		bird.velocity = Vector2.ZERO
		bird.anim_stop_or_blendout()
	super(actor, blackboard)
