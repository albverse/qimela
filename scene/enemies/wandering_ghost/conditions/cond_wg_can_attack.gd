extends ConditionLeaf
class_name CondWGCanAttack

## 检查幽灵是否可以发动攻击：显现状态 + 玩家在攻击范围内 + 攻击CD就绪。

func tick(actor: Node, _blackboard: Blackboard) -> int:
	var ghost: WanderingGhost = actor as WanderingGhost
	if ghost == null:
		return FAILURE
	if not ghost._is_visible:
		return FAILURE
	if ghost._attack_cd_t > 0.0:
		return FAILURE
	if not ghost.is_player_in_attack_area():
		return FAILURE
	return SUCCESS
