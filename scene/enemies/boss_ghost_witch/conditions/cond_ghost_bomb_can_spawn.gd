extends ConditionLeaf
class_name CondGhostBombCanSpawn

@export var max_count: int = 3

func tick(actor: Node, _bb: Blackboard) -> int:
	var bombs := actor.get_tree().get_nodes_in_group("ghost_bomb")
	return SUCCESS if bombs.size() < max_count else FAILURE
