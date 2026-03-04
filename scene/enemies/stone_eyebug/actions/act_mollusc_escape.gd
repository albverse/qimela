extends ActionLeaf
class_name ActMolluscEscape

## 软体虫逃跑：持续跑，前方墙/断崖则掉头；玩家进入威胁距离则重规划。
## 永远返回 RUNNING（兜底分支）。

const GRAVITY: float = 800.0


func before_run(actor: Node, _blackboard: Blackboard) -> void:
	var mollusc := actor as Mollusc
	if mollusc == null:
		return
	mollusc.escape_remaining = mollusc.escape_dist


func tick(actor: Node, _blackboard: Blackboard) -> int:
	var mollusc := actor as Mollusc
	if mollusc == null:
		return FAILURE

	# 死亡动画播放中：冻结移动，等待 _physics_process 销毁
	if mollusc._die_anim_playing:
		mollusc.velocity = Vector2.ZERO
		return RUNNING

	# 受击硬直中：冻结移动，等待 hurt 动画和 hurt_lock_t 结束
	if mollusc.is_hurt:
		mollusc.velocity = Vector2.ZERO
		return RUNNING

	var dt := mollusc.get_physics_process_delta_time()

	# 重规划（玩家进入威胁距离）
	mollusc.plan_escape_if_player_near()

	# 死路/断崖检测 → 掉头
	if mollusc.is_wall_ahead() or not mollusc.is_floor_ahead():
		mollusc.escape_dir_x = -mollusc.escape_dir_x
		mollusc.escape_remaining = mollusc.escape_dist

	# 移动
	mollusc.velocity.x = float(mollusc.escape_dir_x) * mollusc.escape_speed
	mollusc.velocity.y += GRAVITY * dt
	mollusc.move_and_slide()

	# 更新剩余逃跑距离
	var moved: float = absf(mollusc.velocity.x) * dt
	mollusc.escape_remaining = max(mollusc.escape_remaining - moved, 0.0)
	if mollusc.escape_remaining <= 0.0:
		# 本轮逃跑完成，重新规划
		mollusc.escape_remaining = mollusc.escape_dist

	# 播放跑步动画
	if not mollusc.anim_is_playing(&"run"):
		mollusc.anim_play(&"run", true, true)

	# 永远 RUNNING
	return RUNNING


func interrupt(actor: Node, blackboard: Blackboard) -> void:
	var mollusc := actor as Mollusc
	if mollusc != null:
		mollusc.velocity = Vector2.ZERO
	super(actor, blackboard)
