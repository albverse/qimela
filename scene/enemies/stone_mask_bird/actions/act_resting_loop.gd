extends ActionLeaf
class_name ActRestingLoop

## 7.1 Act_RestingLoop
## 倒地休息循环。播放 rest_loop。
## 所有离开 RESTING 的转换一律先进入 WAKING，由 act_wake_up 播放 wake_up 后再决定下一模式。

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
			# 先播 wake_up，act_wake_up 完成后自动进入 FLYING_ATTACK
			bird.mode = StoneMaskBird.Mode.WAKING
			return SUCCESS

	if bird.can_start_hunt():
		var target := bird.find_nearest_walk_monster_in_range(bird.rest_hunt_trigger_px)
		if target != null:
			bird.hunt_target = target
			# rest_hunt_requested=true 告知 act_wake_up 完成后进入 HUNTING 而非 FLYING_ATTACK
			bird.rest_hunt_requested = true
			bird.mode = StoneMaskBird.Mode.WAKING
			return SUCCESS

	# 永远 RUNNING，直到被更高优先级的 Seq 打断
	return RUNNING


func interrupt(actor: Node, blackboard: Blackboard) -> void:
	super(actor, blackboard)
