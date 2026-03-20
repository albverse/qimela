extends ConditionLeaf
class_name CondPlayerAboveBoss

## 检查玩家是否在 Boss 上方

@export var y_threshold: float = 30.0

func tick(actor: Node, _bb: Blackboard) -> int:
	var boss: BossGhostWitch = actor as BossGhostWitch
	if boss == null:
		return FAILURE
	var player: Node2D = boss.get_priority_attack_target()
	if player == null:
		return FAILURE
	# Godot Y 轴向下，actor.y > player.y 表示玩家在上方
	var y_diff: float = actor.global_position.y - player.global_position.y
	return SUCCESS if y_diff > y_threshold else FAILURE
