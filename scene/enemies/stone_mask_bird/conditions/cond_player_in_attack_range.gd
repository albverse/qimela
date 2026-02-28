extends ConditionLeaf
class_name CondPlayerInAttackRange

## 检查玩家是否在 StoneMaskBird 的攻击范围内。
## 优先使用 AttackArea（Area2D, collision_mask=2）的 overlaps_body 检测；
## AttackArea 不可用时退化为 attack_range_px 距离检测（兜底）。
## SUCCESS → 玩家在攻击范围内 → 执行 ActAttackLoopDash。
## FAILURE → 玩家不在范围内 → 退让给 ActChasePlayer。

func tick(actor: Node, _blackboard: Blackboard) -> int:
	var bird := actor as StoneMaskBird
	if bird == null:
		return FAILURE

	var player := bird._get_player()
	if player == null:
		return FAILURE

	# 优先：Area2D overlap（物理层正确时最精确）
	if bird._attack_area != null:
		if bird._attack_area.overlaps_body(player):
			return SUCCESS

	# 兜底：距离检测（AttackArea 尚未初始化 / 层配置异常时保证功能）
	var dist := bird.global_position.distance_to(player.global_position)
	if dist <= bird.attack_range_px:
		return SUCCESS

	return FAILURE
