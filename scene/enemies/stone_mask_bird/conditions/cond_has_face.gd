extends ConditionLeaf
class_name CondHasFace

## 检查 StoneMaskBird.has_face 是否为 true。
## has_face=true 时返回 SUCCESS，否则 FAILURE。
## shoot_face_committed=true 时同样返回 SUCCESS，
## 防止发射瞬间 has_face 变 false 导致 Seq_ShootFace 中断进行中的动画。

func tick(actor: Node, _blackboard: Blackboard) -> int:
	var bird := actor as StoneMaskBird
	if bird == null:
		return FAILURE
	if bird.has_face or bird.shoot_face_committed:
		return SUCCESS
	return FAILURE
