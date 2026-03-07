extends ConditionLeaf
class_name CondMolluscPlayerInRange

## 检查玩家是否在软体虫攻击范围内（自给自足感知）。

func tick(actor: Node, _blackboard: Blackboard) -> int:
	var mollusc := actor as Mollusc
	if mollusc == null:
		return FAILURE
	# 入壳无敌阶段：禁止攻击中断（enter_shell/flip_to_normal 不可被 Seq_Attack 打断）
	if mollusc.is_entering_shell:
		return FAILURE
	if mollusc.is_player_in_attack_range():
		return SUCCESS
	return FAILURE
