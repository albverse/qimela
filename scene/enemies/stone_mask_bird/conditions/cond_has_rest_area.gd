extends ConditionLeaf
class_name CondHasRestArea

## 检查场景中是否存在至少一个 rest_area 节点（group: "rest_area"）。
## 避免 RETURN_TO_REST 在无目标时抖动或卡死。

func tick(actor: Node, _blackboard: Blackboard) -> int:
	var rest_areas := actor.get_tree().get_nodes_in_group("rest_area")
	if rest_areas.is_empty():
		return FAILURE
	return SUCCESS
