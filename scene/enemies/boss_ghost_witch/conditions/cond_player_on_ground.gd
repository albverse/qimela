extends ConditionLeaf
class_name CondPlayerOnGround

## 检查玩家是否在地面上（与 Boss 同一高度）

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
			var y_diff: float = abs(p.global_position.y - actor.global_position.y)
			if y_diff <= y_threshold:
				return SUCCESS
	return FAILURE
