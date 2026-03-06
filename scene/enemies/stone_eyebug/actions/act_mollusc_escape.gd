extends ActionLeaf
class_name ActMolluscEscape

## 软体虫逃跑：持续跑，前方墙/断崖则掉头；玩家进入威胁距离则重规划。
## 永远返回 RUNNING（兜底分支）。

const GRAVITY: float = 800.0


func before_run(actor: Node, _blackboard: Blackboard) -> void:
	var mollusc := actor as Mollusc
	if mollusc == null:
		return
	if mollusc.escape_remaining <= 0.0:
		mollusc.escape_remaining = mollusc.escape_dist


func tick(actor: Node, _blackboard: Blackboard) -> int:
	var mollusc := actor as Mollusc
	if mollusc == null:
		return FAILURE

	# 受击硬直/眩晕中：冻结移动
	if mollusc.is_hurt or mollusc.is_stunned():
		mollusc.velocity = Vector2.ZERO
		if mollusc.is_hurt and not mollusc.anim_is_playing(&"hurt"):
			mollusc.anim_play(&"hurt", false, false)
		elif mollusc.is_stunned() and not mollusc.anim_is_playing(&"weak_stun"):
			mollusc.anim_play(&"weak_stun", true, false)
		return RUNNING

	var dt := mollusc.get_physics_process_delta_time()

	if mollusc.should_trigger_forced_breakout():
		mollusc.trigger_forced_breakout()

	# 重规划（玩家进入威胁距离）
	var player_near: bool = mollusc.is_player_near_threat()
	mollusc.plan_escape_if_player_near()

	# 若玩家已不在威胁范围，且本轮逃跑距离已消耗完，则退出本分支（交给 Idle）。
	if not player_near and mollusc.escape_remaining <= 0.0:
		mollusc.clear_idle_hit_escape_request()
		mollusc.velocity = Vector2.ZERO
		return FAILURE

	# 死路/断崖检测 → 掉头
	# 破局越位阶段优先越位：仅当“玩家后方同向也有墙”时才允许因前墙掉头。
	if (mollusc.is_wall_ahead() and mollusc.should_flip_on_wall()) or not mollusc.is_floor_ahead():
		mollusc.escape_dir_x = -mollusc.escape_dir_x

	var prev_pos: Vector2 = mollusc.global_position
	# 移动
	mollusc.velocity.x = float(mollusc.escape_dir_x) * mollusc.escape_speed
	mollusc.velocity.y += GRAVITY * dt
	mollusc.move_and_slide()

	# 更新剩余逃跑距离
	var moved: float = absf(mollusc.global_position.x - prev_pos.x)
	mollusc.escape_remaining = max(mollusc.escape_remaining - moved, 0.0)
	mollusc.update_breakout_post_combo()

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
