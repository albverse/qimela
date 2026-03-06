extends ActionLeaf
class_name ActMolluscIdle

## 软体虫待机：玩家远离、无壳可回、不需移动时播 idle 循环，始终 RUNNING。
## 由 SelectorReactive 兜底（所有高优先级分支均 FAILURE 时触发）。
## 特例：idle 超过 shell_return_idle_delay 且场景中无空壳，触发小幅随机游走。

const WANDER_GRAVITY: float = 800.0

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func before_run(actor: Node, _blackboard: Blackboard) -> void:
	var mollusc := actor as Mollusc
	if mollusc == null:
		return
	mollusc.set_idle_state_active(true)


func tick(actor: Node, _blackboard: Blackboard) -> int:
	var mollusc := actor as Mollusc
	if mollusc == null:
		return FAILURE
	mollusc.set_idle_state_active(true)

	if mollusc.is_hurt:
		mollusc.velocity = Vector2.ZERO
		if not mollusc.anim_is_playing(&"hurt"):
			mollusc.anim_play(&"hurt", false, false)
		return RUNNING

	# 无壳 + idle 超时：小幅随机游走（避免长时间原地静止）
	if mollusc.is_shell_return_window_open() and mollusc.find_empty_shell() == null:
		if mollusc.escape_remaining <= 0.0:
			_rng.randomize()
			mollusc.escape_remaining = 60.0 + _rng.randf() * 60.0  # 60~120 px
			mollusc.escape_dir_x = 1 if _rng.randi() % 2 == 0 else -1
		var dt := mollusc.get_physics_process_delta_time()
		if (mollusc.is_wall_ahead() and mollusc.should_flip_on_wall()) or not mollusc.is_floor_ahead():
			mollusc.escape_dir_x = -mollusc.escape_dir_x
		var prev_x: float = mollusc.global_position.x
		mollusc.velocity.x = float(mollusc.escape_dir_x) * mollusc.escape_speed
		mollusc.velocity.y += WANDER_GRAVITY * dt
		mollusc.move_and_slide()
		var moved: float = absf(mollusc.global_position.x - prev_x)
		mollusc.escape_remaining = max(mollusc.escape_remaining - moved, 0.0)
		if not mollusc.anim_is_playing(&"run"):
			mollusc.anim_play(&"run", true, true)
		return RUNNING

	mollusc.velocity = Vector2.ZERO
	if not mollusc.anim_is_playing(&"idle"):
		mollusc.anim_play(&"idle", true, true)
	return RUNNING


func interrupt(actor: Node, blackboard: Blackboard) -> void:
	var mollusc := actor as Mollusc
	if mollusc != null:
		mollusc.set_idle_state_active(false)
		mollusc.velocity = Vector2.ZERO
	super(actor, blackboard)
