extends ConditionLeaf
class_name CondMolluscAttackReady

## Mollusc 攻击冷却检查：每次攻击结束后冷却 attack_cd 秒。
## 冷却中返回 FAILURE，让 BT 落到逃跑分支。

func tick(actor: Node, _blackboard: Blackboard) -> int:
	var mollusc := actor as Mollusc
	if mollusc == null:
		return FAILURE
	if Mollusc.now_ms() >= mollusc.next_attack_end_ms:
		return SUCCESS
	return FAILURE
