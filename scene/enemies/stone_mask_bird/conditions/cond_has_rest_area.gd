extends ConditionLeaf
class_name CondHasRestArea

## 检查场景中是否存在可用 rest_area 节点（group: "rest_area"）。
## 避免 RETURN_TO_REST 在无目标时抖动或卡死。

func tick(actor: Node, _blackboard: Blackboard) -> int:
	var bird := actor as StoneMaskBird
	if bird == null:
		return FAILURE
	if bird.has_available_rest_area():
		return SUCCESS
	# 无可用休息点时回到攻击态，避免 mode=RETURN_TO_REST 卡分支。
	if bird.mode == StoneMaskBird.Mode.RETURN_TO_REST:
		bird.mode = StoneMaskBird.Mode.FLYING_ATTACK
		var now := StoneMaskBird.now_sec()
		bird.attack_until_sec = now + bird.attack_duration_sec
		bird.next_attack_sec = now
	return FAILURE
