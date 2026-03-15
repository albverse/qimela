extends ConditionLeaf
class_name CondPlayerOnPlatform

## 检查玩家是否在跳板上（高于 Boss）

@export var y_threshold: float = 50.0

func tick(actor: Node, _bb: Blackboard) -> int:
	var boss: BossGhostWitch = actor as BossGhostWitch
	if boss == null:
		return FAILURE
	var player: Node2D = boss.get_priority_attack_target()
	if player == null:
		return FAILURE
	if player is CharacterBody2D:
		var p: CharacterBody2D = player as CharacterBody2D
		if p.is_on_floor():
			# actor.y > player.y 表示玩家在更高位置（Godot Y 轴向下）
			var y_diff: float = actor.global_position.y - p.global_position.y
			if y_diff > y_threshold:
				return SUCCESS
	return FAILURE
