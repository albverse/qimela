extends ActionLeaf
class_name ActChasePlayer

## Act_ChasePlayer（飞行追击）
## 在 FLYING_ATTACK 模式下，玩家不在攻击范围（AttackArea 外）时执行。
##
## 行为优先级（从高到低）：
##   1. 玩家在追击范围（chase_range_px=200px）内 → fly_move 飞向玩家，RUNNING
##      （一旦玩家进入追击范围则重置悬停计时器）
##   2. 玩家不在范围，无面具，有 walk_monster → 切 HUNTING 狩猎，SUCCESS
##   3. 玩家不在范围，但有可用 rest_area → fly_idle 悬停等待 5s，RUNNING
##      5s 内如果依然不在范围则切 RETURN_TO_REST 回巢，SUCCESS
##   4. 玩家不在范围，无 rest_area，有 rest_area_break → 切 REPAIRING，SUCCESS
##   5. 玩家不在范围，无 rest_area，无 rest_area_break → fly_idle 悬停，RUNNING
##
## 被高优先级序列打断（HURT/STUNNED）由 BT 的 SelectorReactive 自动处理，
## interrupt() 仅做本地状态清理。

const HOVER_RETURN_SEC: float = 5.0

var _hover_elapsed: float = 0.0


func before_run(actor: Node, _blackboard: Blackboard) -> void:
	var bird := actor as StoneMaskBird
	if bird == null:
		return
	_hover_elapsed = 0.0
	if not bird.anim_is_playing(&"fly_move") and not bird.anim_is_playing(&"fly_idle"):
		bird.anim_play(&"fly_idle", true, true)


func tick(actor: Node, _blackboard: Blackboard) -> int:
	var bird := actor as StoneMaskBird
	if bird == null:
		return FAILURE

	var dt := actor.get_physics_process_delta_time()
	var player := bird._get_player()

	# --- 优先级 1: 玩家在追击范围内 → fly_move 飞向玩家 ---
	if player != null:
		var dist := bird.global_position.distance_to(player.global_position)
		if dist <= bird.chase_range_px:
			_hover_elapsed = 0.0  # 玩家进入范围则重置悬停计时
			_fly_toward(bird, player)
			return RUNNING

	# --- 玩家不在追击范围：停止移动 ---
	bird.velocity = Vector2.ZERO

	# --- 优先级 2: 无面具 + 有 walk_monster → 切 HUNTING 狩猎 ---
	if not bird.has_face:
		var walk_monsters := bird.get_tree().get_nodes_in_group("monster")
		for m in walk_monsters:
			if not is_instance_valid(m):
				continue
			if not (m is MonsterWalk or m is MonsterWalkB):
				continue
			var sid = m.get("species_id")
			if sid == &"walk_dark" or sid == &"walk_dark_b":
				var dist_m := bird.global_position.distance_to(m.global_position)
				if dist_m <= bird.hunt_range_px:
					bird.mode = StoneMaskBird.Mode.HUNTING
					return SUCCESS

	# --- 优先级 3: 有可用 rest_area → fly_idle 悬停，最多 5s 后回巢 ---
	var rest_areas := bird.get_tree().get_nodes_in_group("rest_area")
	if not rest_areas.is_empty():
		_ensure_idle_anim(bird)
		_hover_elapsed += dt
		if _hover_elapsed >= HOVER_RETURN_SEC:
			bird.mode = StoneMaskBird.Mode.RETURN_TO_REST
			return SUCCESS
		return RUNNING

	# --- 优先级 4: 无 rest_area，有 rest_area_break → 切换修复模式 ---
	var break_areas := bird.get_tree().get_nodes_in_group("rest_area_break")
	if not break_areas.is_empty():
		bird.mode = StoneMaskBird.Mode.REPAIRING
		return SUCCESS

	# --- 优先级 5: 无任何巢穴 → fly_idle 永久悬停 ---
	_ensure_idle_anim(bird)
	return RUNNING


func _fly_toward(bird: StoneMaskBird, player: Node2D) -> void:
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
	_hover_elapsed = 0.0
	super(actor, blackboard)
