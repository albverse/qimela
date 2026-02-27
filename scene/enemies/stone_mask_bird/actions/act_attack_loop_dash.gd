extends ActionLeaf
class_name ActAttackLoopDash

## 7.3 Act_AttackLoopDash
## 飞行攻击循环：每 dash_cooldown 秒一次 dash_attack + dash_return。
## 目标点 = player.pos + Vector2(0, -attack_offset_y)。
## 攻击时间到期后自动切换到 RETURN_TO_REST（有 rest_area 时）或重置攻击时间。
##
## 内部状态机：HOVERING -> DASHING -> RETURNING -> HOVERING ...
## 全程返回 RUNNING。被打断由 apply_hit() 设置 mode=HURT/STUNNED，BT 自然切走。

enum Phase { HOVERING, DASHING, RETURNING }

var _phase: int = Phase.HOVERING
var _dash_target: Vector2 = Vector2.ZERO
var _has_dealt_damage: bool = false

func before_run(actor: Node, _blackboard: Blackboard) -> void:
	_phase = Phase.HOVERING
	_has_dealt_damage = false


func tick(actor: Node, _blackboard: Blackboard) -> int:
	var bird := actor as StoneMaskBird
	if bird == null:
		return FAILURE

	var now := StoneMaskBird.now_sec()
	var dt: float = actor.get_physics_process_delta_time()
	var player := bird._get_player()

	# --- 攻击时间到期检查 ---
	if now >= bird.attack_until_sec:
		var rest_areas := bird.get_tree().get_nodes_in_group("rest_area")
		if not rest_areas.is_empty():
			bird.mode = StoneMaskBird.Mode.RETURN_TO_REST
			bird.velocity = Vector2.ZERO
			return SUCCESS
		else:
			# 无 rest_area -> 永远攻击，重置计时
			bird.attack_until_sec = now + bird.attack_duration_sec

	match _phase:
		Phase.HOVERING:
			_tick_hovering(bird, dt, now, player)
		Phase.DASHING:
			_tick_dashing(bird, dt, player)
		Phase.RETURNING:
			_tick_returning(bird, dt, now)

	return RUNNING


func _tick_hovering(bird: StoneMaskBird, dt: float, now: float, player: Node2D) -> void:
	# 移动到 hover_point（玩家上方 attack_offset_y）
	if player:
		var hover_point := player.global_position + Vector2(0, -bird.attack_offset_y)
		var to_hover := hover_point - bird.global_position
		var dist := to_hover.length()
		if dist > 5.0:
			bird.velocity = to_hover.normalized() * bird.hover_speed
		else:
			bird.velocity = Vector2.ZERO
	else:
		bird.velocity = Vector2.ZERO

	# 确保播放 fly_idle
	if not bird.anim_is_playing(&"fly_idle"):
		bird.anim_play(&"fly_idle", true, true)

	bird.move_and_slide()

	# 到时间了就开始冲刺
	if now >= bird.next_attack_sec and player:
		_phase = Phase.DASHING
		bird.dash_origin = bird.global_position
		_dash_target = player.global_position
		_has_dealt_damage = false
		bird.anim_play(&"dash_attack", false, true)


func _tick_dashing(bird: StoneMaskBird, dt: float, player: Node2D) -> void:
	# 向玩家位置冲刺
	var to_target := _dash_target - bird.global_position
	var dist := to_target.length()

	if dist > 15.0:
		bird.velocity = to_target.normalized() * bird.dash_speed
		bird.move_and_slide()
		# 命中检测：距离玩家足够近时判定一次伤害
		if not _has_dealt_damage and player:
			var dist_to_player := bird.global_position.distance_to(player.global_position)
			if dist_to_player < 40.0:
				_has_dealt_damage = true
				_deal_dash_damage(bird, player)
	else:
		# 到达冲刺目标 -> 回撤
		_phase = Phase.RETURNING
		bird.anim_play(&"dash_return", false, true)


func _tick_returning(bird: StoneMaskBird, dt: float, now: float) -> void:
	# 冲回 dash_origin
	var to_origin := bird.dash_origin - bird.global_position
	var dist := to_origin.length()

	if dist > 15.0:
		bird.velocity = to_origin.normalized() * bird.dash_speed * 0.8
		bird.move_and_slide()
	else:
		# 回到原点 -> 写下一次攻击时间，回到悬停
		bird.global_position = bird.dash_origin
		bird.velocity = Vector2.ZERO
		bird.next_attack_sec = now + bird.dash_cooldown
		_phase = Phase.HOVERING
		bird.anim_play(&"fly_idle", true, true)


func _deal_dash_damage(bird: StoneMaskBird, player: Node2D) -> void:
	# 冲刺命中：对玩家造成伤害（如果玩家有 take_damage / apply_hit 接口）
	if player.has_method("take_damage"):
		player.take_damage(1)


func interrupt(actor: Node, blackboard: Blackboard) -> void:
	var bird := actor as StoneMaskBird
	if bird:
		bird.velocity = Vector2.ZERO
	_phase = Phase.HOVERING
	_has_dealt_damage = false
	super(actor, blackboard)
