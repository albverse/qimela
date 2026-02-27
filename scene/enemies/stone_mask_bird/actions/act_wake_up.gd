extends ActionLeaf
class_name ActWakeUpUninterruptible

## 7.2 Act_WakeUpUninterruptible（0.5s）
## 播放 wake_up 动画（不可打断）。
## 动画结束后设置 mode=FLYING_ATTACK 并写入攻击计时。

func before_run(actor: Node, _blackboard: Blackboard) -> void:
	var bird := actor as StoneMaskBird
	if bird == null:
		return
	# 播放唤醒动画（一次性，不可打断）
	bird.anim_play(&"wake_up", false, false)
	# 写入攻击时间窗口
	var now := StoneMaskBird.now_sec()
	bird.attack_until_sec = now + bird.attack_duration_sec
	bird.next_attack_sec = now  # 唤醒后立刻可攻击


func tick(actor: Node, _blackboard: Blackboard) -> int:
	var bird := actor as StoneMaskBird
	if bird == null:
		return FAILURE
	# 动画未结束 -> RUNNING（不可打断）
	if not bird.anim_is_finished(&"wake_up"):
		return RUNNING
	# 动画结束 -> 切到飞行攻击
	bird.mode = StoneMaskBird.Mode.FLYING_ATTACK
	return SUCCESS


func interrupt(actor: Node, blackboard: Blackboard) -> void:
	# 仅在被 STUNNED 等强制覆盖时才会到这里
	var bird := actor as StoneMaskBird
	if bird:
		bird.anim_stop_or_blendout()
	super(actor, blackboard)
