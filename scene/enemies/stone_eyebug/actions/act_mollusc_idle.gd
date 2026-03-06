extends ActionLeaf
class_name ActMolluscIdle

## 软体虫待机：玩家远离、无壳可回、不需移动时播 idle 循环，始终 RUNNING。
## 由 SelectorReactive 兜底（所有高优先级分支均 FAILURE 时触发）。
## 发呆约 4s 后如仍无壳可回，做一次随机小位移（~60px, ~70px/s），再回发呆。

const WANDER_TRIGGER_SEC: float = 4.0
const WANDER_DIST: float = 60.0
const WANDER_SPEED: float = 70.0
const GRAVITY: float = 800.0

var _idle_timer: float = 0.0
var _wander_dir: int = 1
var _wander_remaining: float = 0.0
var _in_wander: bool = false
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func before_run(actor: Node, _blackboard: Blackboard) -> void:
	var mollusc := actor as Mollusc
	if mollusc == null:
		return
	mollusc.set_idle_state_active(true)
	_idle_timer = 0.0
	_wander_remaining = 0.0
	_in_wander = false
	_rng.randomize()


func tick(actor: Node, _blackboard: Blackboard) -> int:
	var mollusc := actor as Mollusc
	if mollusc == null:
		return FAILURE
	mollusc.set_idle_state_active(true)

	# 受击硬直：冻结移动
	if mollusc.is_hurt:
		mollusc.velocity = Vector2.ZERO
		if not mollusc.anim_is_playing(&"hurt"):
			mollusc.anim_play(&"hurt", false, false)
		return RUNNING

	var dt := mollusc.get_physics_process_delta_time()

	if _in_wander:
		_tick_wander(mollusc, dt)
	else:
		_tick_idle_rest(mollusc, dt)

	return RUNNING


func _tick_idle_rest(mollusc: Mollusc, dt: float) -> void:
	mollusc.velocity.x = 0.0
	mollusc.velocity.y += GRAVITY * dt
	mollusc.move_and_slide()
	if not mollusc.anim_is_playing(&"idle"):
		mollusc.anim_play(&"idle", true, true)
	_idle_timer += dt
	if _idle_timer >= WANDER_TRIGGER_SEC:
		_start_wander(mollusc)


func _start_wander(mollusc: Mollusc) -> void:
	_in_wander = true
	_idle_timer = 0.0
	_wander_dir = 1 if _rng.randi() % 2 == 0 else -1
	_wander_remaining = WANDER_DIST
	mollusc.anim_play(&"run", true, true)


func _tick_wander(mollusc: Mollusc, dt: float) -> void:
	var prev_x: float = mollusc.global_position.x
	mollusc.velocity.x = float(_wander_dir) * WANDER_SPEED
	mollusc.velocity.y += GRAVITY * dt
	mollusc.move_and_slide()
	# 碰墙掉头
	if mollusc.is_on_wall():
		_wander_dir = -_wander_dir
	var moved: float = absf(mollusc.global_position.x - prev_x)
	_wander_remaining -= moved
	if not mollusc.anim_is_playing(&"run"):
		mollusc.anim_play(&"run", true, true)
	if _wander_remaining <= 0.0:
		_in_wander = false
		_idle_timer = 0.0


func interrupt(actor: Node, blackboard: Blackboard) -> void:
	var mollusc := actor as Mollusc
	if mollusc != null:
		mollusc.set_idle_state_active(false)
		mollusc.velocity = Vector2.ZERO
	_in_wander = false
	_idle_timer = 0.0
	super(actor, blackboard)
