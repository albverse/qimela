extends ConditionLeaf
class_name CondGhostBombCanSpawn

## 检查场上自爆幽灵是否未达上限

@export var max_count: int = 3

func tick(actor: Node, _bb: Blackboard) -> int:
	var bombs: Array[Node] = actor.get_tree().get_nodes_in_group("ghost_bomb")
	return SUCCESS if bombs.size() < max_count else FAILURE
