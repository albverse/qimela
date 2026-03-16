## 检查场上自爆幽灵数量是否未超过上限
extends ConditionLeaf
class_name CondGhostBombCanSpawn

@export var max_count: int = 3

func tick(actor: Node, _bb: Blackboard) -> int:
	var bombs: Array[Node] = actor.get_tree().get_nodes_in_group("ghost_bomb")
	return SUCCESS if bombs.size() < max_count else FAILURE
