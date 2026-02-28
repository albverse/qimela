extends ActionLeaf
class_name ActRestingLoop

## 7.1 Act_RestingLoop
## 倒地休息循环。播放 rest_loop。
## 规则：RESTING 时也可直接触发 has_face/no_face 攻击逻辑，不经过 WAKING。

func before_run(actor: Node, _blackboard: Blackboard) -> void:
	var bird := actor as StoneMaskBird
	if bird:
		bird.anim_play(&"rest_loop", true, true)


func tick(actor: Node, _blackboard: Blackboard) -> int:
	var bird := actor as StoneMaskBird
	if bird == null:
		return FAILURE
	var player := bird._get_player()
	if bird.has_face and player != null:
		var dist_to_player := bird.global_position.distance_to(player.global_position)
		if dist_to_player <= bird.face_shoot_engage_range_px():
			bird.mode = StoneMaskBird.Mode.FLYING_ATTACK
			return SUCCESS

	if bird.can_start_hunt():
		var target := bird.find_nearest_walk_monster_in_range(bird.rest_hunt_trigger_px)
		if target != null:
			bird.hunt_target = target
			bird.rest_hunt_requested = false
			bird.mode = StoneMaskBird.Mode.HUNTING
			return SUCCESS

	# 永远 RUNNING，直到被更高优先级的 Seq 打断
	return RUNNING


func interrupt(actor: Node, blackboard: Blackboard) -> void:
	var bird := actor as StoneMaskBird
	if bird:
		bird.anim_stop_or_blendout()
	super(actor, blackboard)
