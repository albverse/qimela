extends ConditionLeaf
class_name CondPlayerInFaceShootRange

## 检查玩家是否在 StoneMaskBird 的 has_face 发射范围内。
## SUCCESS: distance <= face_shoot_engage_range_px()
## shoot_face_committed=true 时直接返回 SUCCESS，
## 使 Seq_ShootFace 在发射进行中不因玩家离开范围而被 BT 中断。

func tick(actor: Node, _blackboard: Blackboard) -> int:
	var bird := actor as StoneMaskBird
	if bird == null:
		return FAILURE
	if bird.shoot_face_committed:
		return SUCCESS
	var player := bird._get_player()
	if player == null:
		return FAILURE
	var dist := bird.global_position.distance_to(player.global_position)
	if dist <= bird.face_shoot_engage_range_px():
		return SUCCESS
	return FAILURE
