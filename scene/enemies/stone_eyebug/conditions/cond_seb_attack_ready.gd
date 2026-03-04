extends ConditionLeaf
class_name CondSEBAttackReady

## 检查石眼虫攻击冷却是否结束（自管理，不依赖 CooldownDecorator）。

func tick(actor: Node, _blackboard: Blackboard) -> int:
	var seb := actor as StoneEyeBug
	if seb == null:
		return FAILURE
	if not seb.attack_enabled_after_player_retreat:
		return FAILURE
	var gate_ms := maxi(seb.next_attack_end_ms, seb.retreat_attack_lock_end_ms)
	if StoneEyeBug.now_ms() >= gate_ms:
		return SUCCESS
	return FAILURE
