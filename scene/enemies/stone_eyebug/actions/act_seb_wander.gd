extends ActionLeaf
class_name ActSEBWander

## 石眼虫巡走：发呆（idle）→ 随机选走法 → 行走 → 发呆 → 循环。
## 三种走法（walk_lick / walk_backfloat / walk_wriggle）完全随机。
## walk_style_min_hold 防止走法频繁切换。
## 永远返回 RUNNING（兜底分支，只有高优先级分支才中断此动作）。

enum Phase { IDLE, WALK }

var _phase: int = Phase.IDLE
var _idle_end_ms: int = 0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

const WALK_ANIMS: Array = [&"walk_lick", &"walk_backfloat", &"walk_wriggle"]


func before_run(actor: Node, _blackboard: Blackboard) -> void:
	var seb := actor as StoneEyeBug
	if seb == null:
		return
	_rng.randomize()
	_start_idle(seb)


func tick(actor: Node, _blackboard: Blackboard) -> int:
	var seb := actor as StoneEyeBug
	if seb == null:
		return FAILURE

	match _phase:
		Phase.IDLE:
			_tick_idle(seb)
		Phase.WALK:
			_tick_walk(seb)

	# 永远 RUNNING，等高优先级分支中断
	return RUNNING


func _start_idle(seb: StoneEyeBug) -> void:
	_phase = Phase.IDLE
	_idle_end_ms = StoneEyeBug.now_ms() + int(seb.idle_time * 1000.0)
	seb.velocity = Vector2.ZERO
	seb.anim_play(&"idle", true, true)


func _tick_idle(seb: StoneEyeBug) -> void:
	seb.velocity = Vector2.ZERO
	if StoneEyeBug.now_ms() >= _idle_end_ms:
		_start_walk(seb)


func _start_walk(seb: StoneEyeBug) -> void:
	_phase = Phase.WALK
	# 随机朝向
	seb.facing = 1 if _rng.randi() % 2 == 0 else -1
	# 随机走法（完全随机，3 选 1）
	seb.walk_style = _rng.randi() % 3
	seb.walk_style_hold_end_ms = StoneEyeBug.now_ms() + int(seb.walk_style_min_hold * 1000.0)
	_play_walk_anim(seb)


func _play_walk_anim(seb: StoneEyeBug) -> void:
	var anim_name: StringName = WALK_ANIMS[seb.walk_style]
	seb.anim_play(anim_name, true, true)


func _tick_walk(seb: StoneEyeBug) -> void:
	# 行走移动（带重力）
	var dt := seb.get_physics_process_delta_time()
	seb.velocity.x = float(seb.facing) * seb.walk_speed
	seb.velocity.y += 800.0 * dt  # 重力：Layer 1 World(1) 地面
	seb.move_and_slide()

	# 碰到墙壁则掉头
	if seb.is_on_wall():
		seb.facing = -seb.facing

	# 行走一段后回到发呆
	# 简单实现：walk_style_min_hold 结束后随机再选或回发呆
	if StoneEyeBug.now_ms() >= seb.walk_style_hold_end_ms:
		if _rng.randi() % 3 == 0:
			_start_idle(seb)
		else:
			_start_walk(seb)


func interrupt(actor: Node, blackboard: Blackboard) -> void:
	var seb := actor as StoneEyeBug
	if seb != null:
		seb.velocity = Vector2.ZERO
		seb.force_close_hit_windows()  # 安全关窗（通常无开窗，防残留）
	_phase = Phase.IDLE
	super(actor, blackboard)
