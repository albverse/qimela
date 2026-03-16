## 自给自足感知：检测玩家是否在指定范围内
extends ConditionLeaf
class_name CondPlayerInRange

@export var range_px: float = 500.0

func tick(actor: Node, blackboard: Blackboard) -> int:
	var boss: BossGhostWitch = actor as BossGhostWitch
	if boss == null:
		return FAILURE
	var player: Node2D = boss.get_priority_attack_target()
	if player == null:
		return FAILURE
	# 使用水平距离（2D 横向游戏）
	var h_dist: float = abs(player.global_position.x - actor.global_position.x)
	if h_dist <= range_px:
		var actor_id := str(actor.get_instance_id())
		blackboard.set_value("player", player, actor_id)
		return SUCCESS
	return FAILURE
