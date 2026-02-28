extends ActionLeaf
class_name ActRestingLoop

## 7.1 Act_RestingLoop
## 倒地休息循环。播放 rest_loop，永远 RUNNING。
## 新增：RESTING 状态下，100px 内发现 MonsterWalk/MonsterWalkB 时，立刻进入唤醒并准备狩猎。

func before_run(actor: Node, _blackboard: Blackboard) -> void:
	var bird := actor as StoneMaskBird
	if bird:
		bird.anim_play(&"rest_loop", true, true)


func tick(actor: Node, _blackboard: Blackboard) -> int:
	var bird := actor as StoneMaskBird
	if bird == null:
		return FAILURE

	var target := bird.find_nearest_walk_monster_in_range(bird.rest_hunt_trigger_px)
	if target != null:
		bird.hunt_target = target
		bird.rest_hunt_requested = true
		bird.mode = StoneMaskBird.Mode.WAKING
		return SUCCESS

	# 永远 RUNNING，直到被更高优先级的 Seq 打断
	return RUNNING


func interrupt(actor: Node, blackboard: Blackboard) -> void:
	var bird := actor as StoneMaskBird
	if bird:
		bird.anim_stop_or_blendout()
	super(actor, blackboard)
