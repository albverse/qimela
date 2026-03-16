## 检查玩家是否在 Boss 上方
extends ConditionLeaf
class_name CondPlayerAboveBoss

@export var y_threshold: float = 30.0

func tick(actor: Node, _bb: Blackboard) -> int:
	var boss := actor as BossGhostWitch
	if boss == null:
		return FAILURE
	var player: Node2D = boss.get_priority_attack_target()
	if player == null:
		return FAILURE
	var y_diff := actor.global_position.y - player.global_position.y
	return SUCCESS if y_diff > y_threshold else FAILURE
