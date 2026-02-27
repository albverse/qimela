extends ActionLeaf
class_name ActRestingLoop

## 7.1 Act_RestingLoop
## 倒地休息循环。播放 rest_loop，永远 RUNNING。
## 退出条件由外部触发：玩家接近时主脚本将 mode 切为 WAKING。

func before_run(actor: Node, _blackboard: Blackboard) -> void:
	var bird := actor as StoneMaskBird
	if bird:
		bird.anim_play(&"rest_loop", true, true)


func tick(actor: Node, _blackboard: Blackboard) -> int:
	# 永远 RUNNING，直到被更高优先级的 Seq 打断
	return RUNNING


func interrupt(actor: Node, blackboard: Blackboard) -> void:
	var bird := actor as StoneMaskBird
	if bird:
		bird.anim_stop_or_blendout()
	super(actor, blackboard)
