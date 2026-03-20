extends ConditionLeaf
class_name CondPlayerInRange

## 自给自足感知：检测玩家是否在指定水平范围内

@export var range_px: float = 500.0

func tick(actor: Node, blackboard: Blackboard) -> int:
	var boss: BossGhostWitch = actor as BossGhostWitch
	if boss == null:
		return FAILURE
	var player: Node2D = boss.get_priority_attack_target()
	if player == null:
		return FAILURE
	var h_dist: float = abs(player.global_position.x - actor.global_position.x)
	if h_dist <= range_px:
		var actor_id: String = str(actor.get_instance_id())
		blackboard.set_value("player", player, actor_id)
		return SUCCESS
	return FAILURE
