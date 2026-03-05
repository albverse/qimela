extends ConditionLeaf
class_name CondSEBAttackReady

## 检查石眼虫攻击冷却是否结束（自管理，不依赖 CooldownDecorator）。
## 设计确认：必须先由玩家触发 retreat_in，之后等待 attack_cd 才允许攻击。

func tick(actor: Node, _blackboard: Blackboard) -> int:
	var seb := actor as StoneEyeBug
	if seb == null:
		return FAILURE
	if not seb.attack_enabled_after_player_retreat:
		return FAILURE
	if StoneEyeBug.now_ms() >= seb.next_attack_end_ms:
		return SUCCESS
	return FAILURE
