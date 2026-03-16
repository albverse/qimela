## 检查玩家是否在平台上（比 Boss 高出阈值）
extends ConditionLeaf
class_name CondPlayerOnPlatform

@export var y_threshold: float = 50.0

func tick(actor: Node, _bb: Blackboard) -> int:
	var boss := actor as BossGhostWitch
	if boss == null:
		return FAILURE
	var player: Node2D = boss.get_priority_attack_target()
	if player == null:
		return FAILURE
	if player is CharacterBody2D:
		var p := player as CharacterBody2D
		if p.is_on_floor():
			var y_diff := actor.global_position.y - p.global_position.y
			if y_diff > y_threshold:
				return SUCCESS
	return FAILURE
