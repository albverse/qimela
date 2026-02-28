extends ActionLeaf
class_name ActChasePlayer

## Act_ChasePlayer（飞行追击）
## 在 FLYING_ATTACK 模式下，玩家不在攻击范围（AttackArea 外）时执行。
##
## 行为优先级（从高到低）：
##   1. 玩家在追击范围（chase_range_px=200px）内 → fly_move 飞向玩家，RUNNING
##   2. 玩家不在范围，但有可用 rest_area → fly_idle 悬停等待，RUNNING
##   3. 玩家不在范围，无 rest_area，有 rest_area_break → 切 REPAIRING，SUCCESS
##   4. 玩家不在范围，无 rest_area，无 rest_area_break → fly_idle 悬停，RUNNING
##
## 被高优先级序列打断（HURT/STUNNED）由 BT 的 SelectorReactive 自动处理，
## interrupt() 仅做本地状态清理。


func before_run(actor: Node, _blackboard: Blackboard) -> void:
	var bird := actor as StoneMaskBird
	if bird == null:
		return
	if not bird.anim_is_playing(&"fly_move") and not bird.anim_is_playing(&"fly_idle"):
		bird.anim_play(&"fly_idle", true, true)


func tick(actor: Node, _blackboard: Blackboard) -> int:
	var bird := actor as StoneMaskBird
	if bird == null:
		return FAILURE

	var dt := actor.get_physics_process_delta_time()
	var player := bird._get_player()

	# --- 玩家在追击范围内：飞向玩家 ---
	if player != null:
		var dist := bird.global_position.distance_to(player.global_position)
		if dist <= bird.chase_range_px:
			_fly_toward(bird, player, dt)
			return RUNNING

	# --- 玩家不在追击范围 ---
	bird.velocity = Vector2.ZERO

	# 有可用 rest_area：悬停，等攻击时间到期自动回巢
	var rest_areas := bird.get_tree().get_nodes_in_group("rest_area")
	if not rest_areas.is_empty():
		_ensure_idle_anim(bird)
		return RUNNING

	# 无 rest_area，有 rest_area_break → 切换到 REPAIRING 模式
	var break_areas := bird.get_tree().get_nodes_in_group("rest_area_break")
	if not break_areas.is_empty():
		bird.mode = StoneMaskBird.Mode.REPAIRING
		return SUCCESS

	# 无任何巢穴：悬停继续伺机攻击
	_ensure_idle_anim(bird)
	return RUNNING


func _fly_toward(bird: StoneMaskBird, player: Node2D, _dt: float) -> void:
	var to_player := player.global_position - bird.global_position
	bird.velocity = to_player.normalized() * bird.hover_speed
	bird.move_and_slide()
	if not bird.anim_is_playing(&"fly_move"):
		bird.anim_play(&"fly_move", true, true)


func _ensure_idle_anim(bird: StoneMaskBird) -> void:
	if not bird.anim_is_playing(&"fly_idle"):
		bird.anim_play(&"fly_idle", true, true)


func interrupt(actor: Node, blackboard: Blackboard) -> void:
	var bird := actor as StoneMaskBird
	if bird:
		bird.velocity = Vector2.ZERO
	super(actor, blackboard)
