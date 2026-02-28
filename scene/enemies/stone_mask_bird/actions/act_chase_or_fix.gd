extends ActionLeaf
class_name ActChaseOrFix

## 7.3 前置 ChaseAction：
## 1) player 在追击范围内（默认 200px）时，播放 fly_move 并追击。
## 2) 仅当 player 进入 StoneMaskBird 的 AttackRangeArea2D 时返回 SUCCESS，
##    允许后续 Act_AttackLoopDash 执行。
## 3) 若 player 不在追击/攻击范围，且无可回归 rest_area，则尝试寻找 rest_area_break 并维修。

const REPAIR_TICK_SEC := 1.0

var _repair_acc_sec: float = 0.0
var _repair_target: Node2D = null


func before_run(actor: Node, _blackboard: Blackboard) -> void:
	var bird := actor as StoneMaskBird
	if bird == null:
		return
	_repair_acc_sec = 0.0
	_repair_target = null
	bird.anim_play(&"fly_move", true, true)


func tick(actor: Node, _blackboard: Blackboard) -> int:
	var bird := actor as StoneMaskBird
	if bird == null:
		return FAILURE

	var dt: float = actor.get_physics_process_delta_time()
	var player := bird._get_player()

	# --- 攻击范围优先：进入 AttackRangeArea2D 后让出执行权给 Act_AttackLoopDash ---
	if player and bird.is_player_in_attack_area(player):
		bird.velocity = Vector2.ZERO
		_repair_target = null
		_repair_acc_sec = 0.0
		if not bird.anim_is_playing(&"fly_idle"):
			bird.anim_play(&"fly_idle", true, true)
		return SUCCESS

	# --- 追击范围：先追玩家（fly_move）---
	if player and bird.is_player_in_chase_range(player):
		_repair_target = null
		_repair_acc_sec = 0.0
		var to_player := player.global_position - bird.global_position
		if to_player.length() > 4.0:
			bird.velocity = to_player.normalized() * bird.hover_speed
			bird.anim_play(&"fly_move", true, true)
			bird.move_and_slide()
		else:
			bird.velocity = Vector2.ZERO
			bird.anim_play(&"fly_idle", true, true)
		return RUNNING

	# --- 场上无可回归 rest_area，尝试维修 rest_area_break ---
	if _has_any_rest_area(bird):
		bird.velocity = Vector2.ZERO
		bird.anim_play(&"fly_idle", true, true)
		_repair_target = null
		_repair_acc_sec = 0.0
		return RUNNING

	if _repair_target == null or not is_instance_valid(_repair_target):
		_repair_target = _pick_rest_area_break(bird)
		_repair_acc_sec = 0.0

	if _repair_target == null:
		bird.velocity = Vector2.ZERO
		bird.anim_play(&"fly_idle", true, true)
		return RUNNING

	var arrived: bool = _is_arrived_to_target(bird, _repair_target)
	if not arrived:
		var to_break := _repair_target.global_position - bird.global_position
		bird.velocity = to_break.normalized() * bird.return_speed
		bird.anim_play(&"fly_move", true, true)
		bird.move_and_slide()
		return RUNNING

	# 到达损坏巢点：播放维修动画，且每 1s +1 hp，直到完全修复
	bird.global_position = _repair_target.global_position
	bird.velocity = Vector2.ZERO
	bird.anim_play(&"fix_rest_area_loop", true, true)
	_repair_acc_sec += dt
	while _repair_acc_sec >= REPAIR_TICK_SEC:
		_repair_acc_sec -= REPAIR_TICK_SEC
		if _repair_target and _repair_target.has_method("repair_one_point"):
			var repaired := bool(_repair_target.call("repair_one_point"))
			if repaired:
				_repair_target = null
				_repair_acc_sec = 0.0
				bird.anim_play(&"fly_idle", true, true)
				break

	return RUNNING


func interrupt(actor: Node, blackboard: Blackboard) -> void:
	var bird := actor as StoneMaskBird
	if bird:
		bird.velocity = Vector2.ZERO
	_repair_acc_sec = 0.0
	_repair_target = null
	super(actor, blackboard)


func _has_any_rest_area(bird: StoneMaskBird) -> bool:
	return not bird.get_tree().get_nodes_in_group("rest_area").is_empty()


func _pick_rest_area_break(bird: StoneMaskBird) -> Node2D:
	var breaks := bird.get_tree().get_nodes_in_group("rest_area_break")
	if breaks.is_empty():
		return null
	var chosen: Node2D = null
	var best_dist_sq: float = INF
	for n in breaks:
		var area := n as Node2D
		if area == null:
			continue
		var d2 := bird.global_position.distance_squared_to(area.global_position)
		if d2 < best_dist_sq:
			best_dist_sq = d2
			chosen = area
	return chosen


func _is_arrived_to_target(bird: StoneMaskBird, target: Node2D) -> bool:
	if target == null:
		return false
	if target.has_method("is_arrived"):
		if bool(target.call("is_arrived", bird)):
			return true
	return bird.global_position.distance_to(target.global_position) <= bird.reach_rest_px
