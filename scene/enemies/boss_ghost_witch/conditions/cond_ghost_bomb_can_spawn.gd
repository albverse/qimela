extends ConditionLeaf

@export var max_count: int = 3

func tick(actor: Node, _blackboard: Blackboard) -> int:
	if actor == null or actor.get_tree() == null:
		return FAILURE
	var bombs := actor.get_tree().get_nodes_in_group("ghost_bomb")
	return SUCCESS if bombs.size() < max_count else FAILURE
