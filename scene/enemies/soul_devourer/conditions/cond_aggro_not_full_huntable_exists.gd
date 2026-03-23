extends ConditionLeaf
class_name CondSoulDevourerAggroNotFullHuntableExists

## P9：aggro 模式 + not full + 存在可猎杀幽灵。
## 自给自足感知，不依赖其他分支 blackboard 写入。

func tick(actor: Node, _blackboard: Blackboard) -> int:
	var sd: SoulDevourer = actor as SoulDevourer
	if sd == null:
		return FAILURE
	if not sd._aggro_mode:
		return FAILURE
	if sd._is_full:
		return FAILURE
	# huntting_succeed 播放中 → 保持 SUCCESS（防止 SequenceReactive 中断动画）
	if sd._hunt_succeed_playing:
		return SUCCESS
	var ghost: Node2D = sd._find_nearest_huntable_ghost()
	if ghost == null:
		return FAILURE
	return SUCCESS
