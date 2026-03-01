extends ActionLeaf
class_name ActHuntWalkMonster

## Act_HuntWalkMonster（狩猎步行怪获取面具）
## 在 HUNTING 模式下，has_face=false 时执行。
## 找到最近的 walk_dark 怪物，飞过去捕获它，然后戴上面具。
##
## 内部阶段：
##   SEARCHING     → 寻找最近的 walk_monster
##   FLYING_TO_TARGET → fly_move 飞向猎物
##   HUNTING_ANIM  → 播放 hunting 动画（2s），目标立即暂停移动
##   PUTTING_ON_FACE → 播放 no_face_to_has_face 动画，戴上面具
##
## 完成后：has_face=true；若玩家在 face_shoot_range_px 内则直接切 FLYING_ATTACK 发射，否则 RETURN_TO_REST。
## 若狩猎被打断（进入 STUNNED）：目标恢复移动，不销毁。

enum Phase { SEARCHING, FLYING_TO_TARGET, HUNTING_ANIM, PUTTING_ON_FACE }

const CATCH_DIST: float = 30.0

var _phase: int = Phase.SEARCHING
var _anim_started_sec: float = -1.0


func before_run(actor: Node, _blackboard: Blackboard) -> void:
	_phase = Phase.SEARCHING
	_anim_started_sec = -1.0
	var bird := actor as StoneMaskBird
	if bird:
		bird.unfreeze_hunt_target()
		# 若 resting->waking 预置了目标则直接沿用
		if bird.hunt_target == null or not is_instance_valid(bird.hunt_target):
			bird.hunt_target = null


func tick(actor: Node, _blackboard: Blackboard) -> int:
	var bird := actor as StoneMaskBird
	if bird == null:
		return FAILURE

	if bird.mode != StoneMaskBird.Mode.HUNTING:
		bird.unfreeze_hunt_target()
		return SUCCESS

	# 已有面具时直接完成（根据玩家位置决定是立即发射还是先回巢）
	if bird.has_face:
		bird.mode = _decide_post_hunt_mode(bird)
		bird.unfreeze_hunt_target()
		return SUCCESS

	var now := StoneMaskBird.now_sec()

	match _phase:
		Phase.SEARCHING:
			return _tick_searching(bird, now)
		Phase.FLYING_TO_TARGET:
			return _tick_flying_to_target(bird, now)
		Phase.HUNTING_ANIM:
			return _tick_hunting_anim(bird, now)
		Phase.PUTTING_ON_FACE:
			return _tick_putting_on_face(bird, now)

	return RUNNING


func _tick_searching(bird: StoneMaskBird, _now: float) -> int:
	var target := bird.hunt_target
	if target == null or not is_instance_valid(target):
		target = _find_nearest_walk_monster(bird)
	if target == null:
		# 无猎物 → 回到飞行攻击
		bird.mode = StoneMaskBird.Mode.FLYING_ATTACK
		var now := StoneMaskBird.now_sec()
		bird.attack_until_sec = now + bird.attack_duration_sec
		bird.next_attack_sec = now
		return SUCCESS

	bird.hunt_target = target
	_phase = Phase.FLYING_TO_TARGET
	bird.anim_play(&"fly_move", true, true)
	return RUNNING


func _tick_flying_to_target(bird: StoneMaskBird, now: float) -> int:
	if bird.hunt_target == null or not is_instance_valid(bird.hunt_target):
		bird.hunt_target = null
		_phase = Phase.SEARCHING
		return RUNNING

	var to_target := bird.hunt_target.global_position - bird.global_position
	var dist := to_target.length()

	if dist > CATCH_DIST:
		bird.velocity = to_target.normalized() * bird.hunt_speed
		bird.move_and_slide()
		if not bird.anim_is_playing(&"fly_move"):
			bird.anim_play(&"fly_move", true, true)
		return RUNNING

	bird.velocity = Vector2.ZERO
	bird.freeze_hunt_target(bird.hunt_target)
	_phase = Phase.HUNTING_ANIM
	_anim_started_sec = now
	bird.anim_play(&"hunt", false, false)
	return RUNNING


func _tick_hunting_anim(bird: StoneMaskBird, now: float) -> int:
	var target_valid := bird.hunt_target != null and is_instance_valid(bird.hunt_target)

	if bird.anim_is_finished(&"hunt"):
		if target_valid:
			_consume_target(bird)
		bird.unfreeze_hunt_target()
		_phase = Phase.PUTTING_ON_FACE
		_anim_started_sec = now
		bird.anim_play(&"no_face_to_has_face", false, false)
		return RUNNING

	return RUNNING


func _tick_putting_on_face(bird: StoneMaskBird, now: float) -> int:
	if bird.anim_is_finished(&"no_face_to_has_face"):
		bird.has_face = true
		bird.trigger_hunt_cooldown(now)
		bird.hunt_target = null
		bird.unfreeze_hunt_target()
		bird.mode = _decide_post_hunt_mode(bird)
		return SUCCESS

	return RUNNING


func _decide_post_hunt_mode(bird: StoneMaskBird) -> int:
	var player := bird._get_player()
	if player != null and bird.global_position.distance_to(player.global_position) <= bird.face_shoot_engage_range_px():
		return StoneMaskBird.Mode.FLYING_ATTACK
	return StoneMaskBird.Mode.RETURN_TO_REST


func _find_nearest_walk_monster(bird: StoneMaskBird) -> Node2D:
	var monsters := bird.get_tree().get_nodes_in_group("monster")
	var best: Node2D = null
	var best_dist: float = bird.hunt_range_px
	for n in monsters:
		var m := n as Node2D
		if m == null or not is_instance_valid(m):
			continue
		if not (m is MonsterWalk or m is MonsterWalkB):
			continue
		var sid = m.get("species_id")
		if sid != &"walk_dark" and sid != &"walk_dark_b":
			continue
		if "hp" in m and int(m.get("hp")) <= 0:
			continue
		var dist := bird.global_position.distance_to(m.global_position)
		if dist < best_dist:
			best_dist = dist
			best = m
	return best


func _consume_target(bird: StoneMaskBird) -> void:
	var target := bird.hunt_target
	if target == null or not is_instance_valid(target):
		return
	bird.unfreeze_hunt_target()
	target.queue_free()
	bird.hunt_target = null


func interrupt(actor: Node, blackboard: Blackboard) -> void:
	var bird := actor as StoneMaskBird
	if bird:
		bird.velocity = Vector2.ZERO
		bird.unfreeze_hunt_target()
		# 被打断不销毁猎物，恢复后走 WAKE_FROM_STUN 回巢
	_phase = Phase.SEARCHING
	_anim_started_sec = -1.0
	super(actor, blackboard)
