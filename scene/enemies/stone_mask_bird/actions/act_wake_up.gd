extends ActionLeaf
class_name ActWakeUpUninterruptible

## 7.2 Act_WakeUpUninterruptible
## 播放 wake_up 动画（不可打断）。
## 动画结束后设置 mode=FLYING_ATTACK 并写入攻击计时。

var _started: bool = false


func before_run(actor: Node, _blackboard: Blackboard) -> void:
	var bird := actor as StoneMaskBird
	if bird == null:
		return
	_started = true
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

	# 极端情况下（例如外部 interrupt 后状态复入）确保 wake_up 至少被触发一次。
	if not _started:
		before_run(actor, _blackboard)

	if bird.anim_is_finished(&"wake_up"):
		var now := StoneMaskBird.now_sec()
		if bird.rest_hunt_requested and bird.hunt_target != null and is_instance_valid(bird.hunt_target) and bird.can_start_hunt(now):
			bird.mode = StoneMaskBird.Mode.HUNTING
			bird.rest_hunt_requested = false
		else:
			bird.rest_hunt_requested = false
			bird.mode = StoneMaskBird.Mode.FLYING_ATTACK
		return SUCCESS

	return RUNNING


func interrupt(actor: Node, blackboard: Blackboard) -> void:
	_started = false
	super(actor, blackboard)
