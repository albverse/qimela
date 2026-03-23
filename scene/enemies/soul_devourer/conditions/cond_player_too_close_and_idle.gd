extends ConditionLeaf
class_name CondSoulDevourerPlayerTooCloseAndIdle

## P5：玩家在 1 秒内对噬魂犬造成伤害超过 2 HP 时 + 玩家距离 < trigger_dist，
## 触发强制隐身。
## 条件：显现非浮空状态，且 _recent_damage_amount > 2.0，且玩家在触发距离内。

func tick(actor: Node, _blackboard: Blackboard) -> int:
	var sd: SoulDevourer = actor as SoulDevourer
	if sd == null:
		return FAILURE
	# 仅在显现非浮空状态下检查
	if sd._is_floating_invisible or sd._forced_invisible:
		return FAILURE

	# 近期 1 秒内受到超过 2 HP 伤害
	if sd._recent_damage_amount <= 2.0:
		return FAILURE

	# 玩家距离检查（蓝图：forced_invisible_trigger_dist = 100px）
	var player: Node2D = sd.get_priority_attack_target()
	if player == null:
		return FAILURE
	var dist: float = sd.global_position.distance_to(player.global_position)
	if dist > sd.forced_invisible_trigger_dist:
		return FAILURE

	return SUCCESS
