extends ActionLeaf
class_name ActAttackLoopDash

## 7.3 Act_AttackLoopDash
## 飞行攻击循环：先追击，再在攻击 Area2D 内执行 dash_attack + dash_return。
## 若玩家不在攻击范围则优先 fly_move 追击；
## 若玩家既不在攻击范围也不在追击范围，且无可用 rest_area，则寻找 rest_area_break 维修。

enum Phase { CHASING, DASHING, RETURNING, REPAIR_MOVING, REPAIRING }

const DASH_HIT_RADIUS: float = 40.0
const DASH_REACH_DIST: float = 15.0
const DASH_TIMEOUT_SEC: float = 0.7
const RETURN_TIMEOUT_SEC: float = 0.9
const REPAIR_TICK_SEC: float = 1.0

var _phase: int = Phase.CHASING
var _dash_target: Vector2 = Vector2.ZERO
var _has_dealt_damage: bool = false
var _dash_started_sec: float = -1.0
var _return_started_sec: float = -1.0
var _repair_target: Node2D = null
var _repair_acc: float = 0.0


func before_run(actor: Node, _blackboard: Blackboard) -> void:
	_phase = Phase.CHASING
	_has_dealt_damage = false
	_dash_started_sec = -1.0
	_return_started_sec = -1.0
	_repair_target = null
	_repair_acc = 0.0


func tick(actor: Node, _blackboard: Blackboard) -> int:
	var bird := actor as StoneMaskBird
	if bird == null:
		return FAILURE

	var now := StoneMaskBird.now_sec()
	var dt: float = actor.get_physics_process_delta_time()
	var player := bird._get_player()

	if _needs_return_to_rest(bird, now):
		return SUCCESS

	if player and bird.is_player_in_attack_area(player):
		if _phase != Phase.DASHING and _phase != Phase.RETURNING:
			_begin_dash(bird, now, player)
	elif _phase == Phase.DASHING:
		_tick_dashing(bird, now, player)
	elif _phase == Phase.RETURNING:
		_tick_returning(bird, now)
	else:
		_tick_non_attack_behavior(bird, dt, player, now)

	return RUNNING


func _needs_return_to_rest(bird: StoneMaskBird, now: float) -> bool:
	if now < bird.attack_until_sec:
		return false
	var rest_areas := bird.get_tree().get_nodes_in_group("rest_area")
	if not rest_areas.is_empty():
		bird.mode = StoneMaskBird.Mode.RETURN_TO_REST
		bird.velocity = Vector2.ZERO
		return true
	bird.attack_until_sec = now + bird.attack_duration_sec
	return false


func _tick_non_attack_behavior(bird: StoneMaskBird, dt: float, player: Node2D, now: float) -> void:
	if player and bird.is_player_in_chase_range(player):
		_phase = Phase.CHASING
		var to_player := player.global_position - bird.global_position
		if to_player.length() > 4.0:
			bird.velocity = to_player.normalized() * bird.hover_speed
		else:
			bird.velocity = Vector2.ZERO
		bird.move_and_slide()
		bird.anim_play(&"fly_move", true, true)
		_repair_target = null
		_repair_acc = 0.0
		return

	var has_rest_area := not bird.get_tree().get_nodes_in_group("rest_area").is_empty()
	if (not has_rest_area) and (player == null or not bird.is_player_in_chase_range(player)):
		_handle_repair_behavior(bird, dt)
		return

	_phase = Phase.CHASING
	bird.velocity = Vector2.ZERO
	bird.anim_play(&"fly_idle", true, true)


func _begin_dash(bird: StoneMaskBird, now: float, player: Node2D) -> void:
	if now < bird.next_attack_sec:
		bird.velocity = Vector2.ZERO
		bird.anim_play(&"fly_idle", true, true)
		return
	_phase = Phase.DASHING
	bird.dash_origin = bird.global_position
	_dash_target = player.global_position
	_has_dealt_damage = false
	_dash_started_sec = now
	bird.anim_play(&"dash_attack", false, true)


func _tick_dashing(bird: StoneMaskBird, now: float, player: Node2D) -> void:
	var to_target := _dash_target - bird.global_position
	var dist := to_target.length()

	if dist > DASH_REACH_DIST:
		bird.velocity = to_target.normalized() * bird.dash_speed
		bird.move_and_slide()

	if not _has_dealt_damage and player:
		if bird.global_position.distance_to(player.global_position) <= DASH_HIT_RADIUS:
			_has_dealt_damage = true
			_deal_dash_damage(player)
			_start_returning(bird, now)
			return

	if dist <= DASH_REACH_DIST or bird.anim_is_finished(&"dash_attack") or (_dash_started_sec > 0.0 and now - _dash_started_sec >= DASH_TIMEOUT_SEC):
		_start_returning(bird, now)


func _start_returning(bird: StoneMaskBird, now: float) -> void:
	_phase = Phase.RETURNING
	_return_started_sec = now
	bird.anim_play(&"dash_return", false, true)


func _tick_returning(bird: StoneMaskBird, now: float) -> void:
	var to_origin := bird.dash_origin - bird.global_position
	var dist := to_origin.length()

	if dist > DASH_REACH_DIST:
		bird.velocity = to_origin.normalized() * bird.dash_speed * 0.8
		bird.move_and_slide()

	if dist <= DASH_REACH_DIST or bird.anim_is_finished(&"dash_return") or (_return_started_sec > 0.0 and now - _return_started_sec >= RETURN_TIMEOUT_SEC):
		bird.global_position = bird.dash_origin
		bird.velocity = Vector2.ZERO
		bird.next_attack_sec = now + bird.dash_cooldown
		_phase = Phase.CHASING
		_dash_started_sec = -1.0
		_return_started_sec = -1.0
		bird.anim_play(&"fly_move", true, true)


func _handle_repair_behavior(bird: StoneMaskBird, dt: float) -> void:
	if _repair_target == null or not is_instance_valid(_repair_target):
		_repair_target = _find_nearest_rest_area_break(bird)
		_repair_acc = 0.0
		if _repair_target == null:
			bird.velocity = Vector2.ZERO
			bird.anim_play(&"fly_idle", true, true)
			return

	var to_target := _repair_target.global_position - bird.global_position
	if to_target.length() > bird.reach_rest_px:
		_phase = Phase.REPAIR_MOVING
		bird.velocity = to_target.normalized() * bird.return_speed
		bird.move_and_slide()
		bird.anim_play(&"fly_move", true, true)
		return

	_phase = Phase.REPAIRING
	bird.global_position = _repair_target.global_position
	bird.velocity = Vector2.ZERO
	bird.anim_play(&"fix_rest_area_loop", true, true)

	_repair_acc += dt * bird.repair_speed_per_sec
	while _repair_acc >= REPAIR_TICK_SEC:
		_repair_acc -= REPAIR_TICK_SEC
		if _repair_target.has_method("repair_tick"):
			var repaired: bool = bool(_repair_target.call("repair_tick", 1))
			if repaired:
				_repair_target = null
				_phase = Phase.CHASING
				bird.anim_play(&"fly_idle", true, true)
				break


func _find_nearest_rest_area_break(bird: StoneMaskBird) -> Node2D:
	var all := bird.get_tree().get_nodes_in_group("rest_area_break")
	if all.is_empty():
		return null
	var best: Node2D = null
	var best_d2 := INF
	for n in all:
		var area := n as Node2D
		if area == null:
			continue
		var d2 := bird.global_position.distance_squared_to(area.global_position)
		if d2 < best_d2:
			best_d2 = d2
			best = area
	return best


func _deal_dash_damage(player: Node2D) -> void:
	if player.has_method("take_damage"):
		player.take_damage(1)


func interrupt(actor: Node, blackboard: Blackboard) -> void:
	var bird := actor as StoneMaskBird
	if bird:
		bird.velocity = Vector2.ZERO
	_phase = Phase.CHASING
	_has_dealt_damage = false
	_dash_started_sec = -1.0
	_return_started_sec = -1.0
	_repair_target = null
	_repair_acc = 0.0
	super(actor, blackboard)
