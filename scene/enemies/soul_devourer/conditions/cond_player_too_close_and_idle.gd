extends ConditionLeaf
class_name CondSoulDevourerPlayerTooCloseAndIdle

## P5：强制隐身触发 — 暂时禁用，排查行为冲突后再启用。
## 原条件：显现非浮空 + 1s 内伤害>2HP + 玩家距离<trigger_dist

func tick(_actor: Node, _blackboard: Blackboard) -> int:
	# ★ 暂时禁用：排查 aggro 行为冲突
	return FAILURE
