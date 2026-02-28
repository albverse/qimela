extends ConditionLeaf
class_name CondHasFace

## 检查 StoneMaskBird.has_face 是否为 true。
## has_face=true 时返回 SUCCESS，否则 FAILURE。

func tick(actor: Node, _blackboard: Blackboard) -> int:
	var bird := actor as StoneMaskBird
	if bird == null:
		return FAILURE
	if bird.has_face:
		return SUCCESS
	return FAILURE
