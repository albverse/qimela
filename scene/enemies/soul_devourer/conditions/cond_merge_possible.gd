extends ConditionLeaf
class_name CondSoulDevourerMergePossible

## 漂浮隐身状态下，检查合体条件：
## 场上有另一只漂浮隐身的 SoulDevourer，且本实例 ID 较小（发起方）。

func tick(actor: Node, _blackboard: Blackboard) -> int:
	var sd: SoulDevourer = actor as SoulDevourer
	if sd == null:
		return FAILURE
	if not sd._aggro_mode:
		return FAILURE
	if not sd._is_floating_invisible:
		return FAILURE
	if sd._can_initiate_merge():
		return SUCCESS
	return FAILURE
