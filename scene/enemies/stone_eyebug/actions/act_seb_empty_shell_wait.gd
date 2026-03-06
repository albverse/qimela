extends ActionLeaf
class_name ActSEBEmptyShellWait

## 石眼虫空壳等待：软体逃出后，壳体保持 EMPTY_SHELL 状态原地播 empty_loop，
## 直到软体回壳（notify_shell_restored 切换 mode 为 IN_SHELL）。
## SelectorReactive 会在 mode 不再是 EMPTY_SHELL 时自动中断本节点。

func before_run(actor: Node, _blackboard: Blackboard) -> void:
	var seb := actor as StoneEyeBug
	if seb == null:
		return
	seb.velocity = Vector2.ZERO
	seb.anim_play(&"empty_loop", true, true)


func tick(actor: Node, _blackboard: Blackboard) -> int:
	var seb := actor as StoneEyeBug
	if seb == null:
		return FAILURE
	seb.velocity = Vector2.ZERO
	if not seb.anim_is_playing(&"empty_loop"):
		seb.anim_play(&"empty_loop", true, true)
	return RUNNING


func interrupt(actor: Node, blackboard: Blackboard) -> void:
	var seb := actor as StoneEyeBug
	if seb != null:
		seb.velocity = Vector2.ZERO
	super(actor, blackboard)
