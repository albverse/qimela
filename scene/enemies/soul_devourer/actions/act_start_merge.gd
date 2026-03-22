extends ActionLeaf
class_name ActSoulDevourerStartMerge

## =============================================================================
## act_start_merge — 发起合体流程（漂浮隐身 + cond_merge_possible 通过时）
## =============================================================================
## 设置 _merging = true，触发 P3 act_move_to_partner。
## 同时通知 partner 也进入 _merging。
## =============================================================================

func tick(actor: Node, _blackboard: Blackboard) -> int:
	var sd: SoulDevourer = actor as SoulDevourer
	if sd == null:
		return FAILURE

	var partner: SoulDevourer = sd._get_merge_partner()
	if partner == null:
		return FAILURE

	sd._merging = true
	partner._merging = true

	return SUCCESS
