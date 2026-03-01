extends ActionLeaf
class_name ActRestingLoop

## 7.1 Act_RestingLoop
## 倒地休息循环。播放 rest_loop。
## 规则：RESTING 离开时统一先进入 WAKING，再根据条件转入攻击/狩猎。

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
			bird.rest_hunt_requested = false
			bird.mode = StoneMaskBird.Mode.WAKING
			if bird.anim_debug_log_enabled:
				print("[StoneMaskBird][RestingLoop] trigger wake_up for face-shoot")
			return SUCCESS

	if bird.can_start_hunt():
		var target := bird.find_nearest_walk_monster_in_range(bird.rest_hunt_trigger_px)
		if target != null:
			bird.hunt_target = target
			bird.rest_hunt_requested = true
			bird.mode = StoneMaskBird.Mode.WAKING
			if bird.anim_debug_log_enabled:
				print("[StoneMaskBird][RestingLoop] trigger wake_up for hunting target=%s" % str(target))
			return SUCCESS

	# 永远 RUNNING，直到被更高优先级的 Seq 打断
	return RUNNING


func interrupt(actor: Node, blackboard: Blackboard) -> void:
	var bird := actor as StoneMaskBird
	if bird:
		bird.anim_stop_or_blendout()
	super(actor, blackboard)
