extends ActionLeaf
class_name ActWakeUpUninterruptible

## 7.2 Act_WakeUpUninterruptible（0.5s）
## 播放 wake_up 动画（不可打断）。
## 动画结束后设置 mode=FLYING_ATTACK 并写入攻击计时。
##
## Beehave 2.9.2 / SelectorReactive + SequenceReactive 下，running 子节点不会反复触发 before_run。
## 因此这里不能只依赖 anim_is_finished("wake_up")，还需要本地超时兜底，避免状态机因动画回调缺失而永久 RUNNING。

const WAKE_DURATION_SEC: float = 0.5

var _wake_deadline_sec: float = -1.0
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
	_wake_deadline_sec = now + WAKE_DURATION_SEC
	bird.attack_until_sec = now + bird.attack_duration_sec
	bird.next_attack_sec = now  # 唤醒后立刻可攻击


func tick(actor: Node, _blackboard: Blackboard) -> int:
	var bird := actor as StoneMaskBird
	if bird == null:
		return FAILURE

	# 极端情况下（例如外部 interrupt 后状态复入）确保 wake_up 至少被触发一次。
	if not _started:
		before_run(actor, _blackboard)

	var now := StoneMaskBird.now_sec()
	if bird.anim_is_finished(&"wake_up") or now >= _wake_deadline_sec:
		if bird.rest_hunt_requested and bird.hunt_target != null and is_instance_valid(bird.hunt_target) and bird.can_start_hunt(now):
			bird.mode = StoneMaskBird.Mode.HUNTING
			bird.rest_hunt_requested = false
		else:
			bird.rest_hunt_requested = false
			bird.mode = StoneMaskBird.Mode.FLYING_ATTACK
		return SUCCESS

	# 动画仍在播放（或回调缺失但未到 0.5s）
	return RUNNING


func interrupt(actor: Node, blackboard: Blackboard) -> void:
	# 仅在被 STUNNED 等强制覆盖时才会到这里
	var bird := actor as StoneMaskBird
	if bird:
		bird.anim_stop_or_blendout()
	_started = false
	_wake_deadline_sec = -1.0
	super(actor, blackboard)
