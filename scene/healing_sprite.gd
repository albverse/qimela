extends Node2D
class_name HealingSprite

enum State { IDLE_IN_WORLD, ACQUIRE, ORBIT, VANISH, CONSUMED }

# ============================================================
# 视觉节点（未来换 Spine2D：把 visual_path 指到 Spine 节点即可）
# ============================================================
@export var visual_path: NodePath = ^"Sprite2D"
@onready var visual: Node2D = get_node_or_null(visual_path) as Node2D


# ============================================================
# 触发/吸附参数（核心参数：吸附范围 150px）
# ============================================================
@export var acquire_range: float = 150.0
# 玩家靠近触发距离(px)

@export var acquire_delay: float = 1.0
# 触发后延迟(s)再开始加速飞（锁链命中可跳过）

@export var chain_hit_instant: bool = true
# 锁链命中时是否跳过延迟（更跟手）

@export var acquire_accel: float = 800.0
# 追向目标的加速度(px/s^2)

@export var acquire_max_speed: float = 300.0
# 追向目标的最大速度(px/s)

@export var attach_distance: float = 0
# 接近到该距离(px)后切换为 ORBIT（锁轨）
# ✅ 特殊约定：attach_distance <= 0 时，不进入 ORBIT，而是永远使用“追逐环绕目标点”模式（你现在喜欢的效果）


# ============================================================
# 环绕轨道参数（核心：半径 ~60px，伪3D感）
# ============================================================
@export var orbit_radius_x: float = 80.0
@export var orbit_radius_y: float = 36.0
# 建议 y < x，椭圆更像“卫星绕行”且有纵深

@export var orbit_speed: float = 2.0
# 角速度(rad/s)

@export var scale_min: float = 0.7
@export var scale_max: float = 1.0

# 两只精灵的轨道略有不同，进一步降低“完全重叠”
@export var radius_delta_x_by_index: float = 6.0
@export var radius_delta_y_by_index: float = 4.0


# ============================================================
# “追逐环绕目标点”模式（attach_distance<=0）参数
# ============================================================
@export var orbit_chase_accel: float = 900.0
@export var orbit_chase_max_speed: float = 360.0

@export var orbit_chase_damping: float = 0.92
# 速度阻尼：越接近 1 越“稳跟”；越小越“漂移”


# ============================================================
# 两只精灵不重叠：相位分离 + 微差异（速度/摆动）
# ============================================================
@export var phase_settle_speed: float = 12.0
# 相位收敛速度(1/s)，越大越快分开（仍不会瞬移）

@export var phase_jitter_max: float = 0.18
# 每只精灵固定相位扰动上限(rad)，避免完美对称导致偶发重叠

@export var speed_mult_min: float = 0.98
@export var speed_mult_max: float = 1.02
# 每只精灵角速度倍率微差异

@export var wobble_amp: float = 0.08
@export var wobble_freq_min: float = 0.65
@export var wobble_freq_max: float = 0.95
# 轻微摆动，避免两只长期同相

@export var use_opposite_orbit_dir: bool = false
# 是否一顺一逆（更有生命感，但会周期性交叉）


# ============================================================
# 玩家跳跃滞后（核心：0.3 秒）
# ============================================================
@export var vertical_lag_time: float = 0.30
# 只对 center 的 Y 做指数平滑追随（自然的“慢半拍”）


# ============================================================
# 可选：消失过渡（默认关；为Spine2D留替换点）
# ============================================================
@export var use_vanish_transition: bool = false
@export var vanish_time: float = 0.18

@export var vanish_shader: Shader = null
@export var dissolve_param_name: StringName = &"burn"
var _dissolve_mat: ShaderMaterial = null


# ============================================================
# 运行时状态
# ============================================================
var state: int = State.IDLE_IN_WORLD
var player: Player = null

var orbit_index: int = 0              # 0/1：由 Player.try_collect_healing_sprite 决定
var orbit_angle: float = 0.0          # 轨道基角

var velocity: Vector2 = Vector2.ZERO
var acquire_timer: float = 0.0

# center 的平滑缓存（实现跳跃滞后）
var _center_smoothed: Vector2 = Vector2.ZERO

# 相位/微差异
var phase_offset: float = 0.0
var phase_target: float = 0.0
var phase_jitter: float = 0.0

var orbit_speed_mult: float = 1.0
var wobble_freq: float = 0.8
var wobble_phase: float = 0.0
var orbit_dir: float = 1.0


func _ready() -> void:
	add_to_group("healing_sprite")


func _exit_tree() -> void:
	# 防止 Player 残留引用
	if player != null and is_instance_valid(player) and player.has_method("remove_healing_sprite"):
		player.call("remove_healing_sprite", self)


func _physics_process(dt: float) -> void:
	match state:
		State.IDLE_IN_WORLD:
			_check_player_nearby()
		State.ACQUIRE:
			_update_acquire(dt)
		State.ORBIT:
			_update_orbit(dt)
		State.VANISH:
			pass
		State.CONSUMED:
			pass


# ------------------------------------------------------------
# 触发：靠近玩家
# ------------------------------------------------------------
func _check_player_nearby() -> void:
	if player != null:
		return

	var p: Player = get_tree().get_first_node_in_group("player") as Player
	if p == null:
		return

	if global_position.distance_to(p.global_position) < acquire_range:
		_start_acquire(p, -1, false)


# ------------------------------------------------------------
# 触发：锁链命中
# 重要：返回 1 才会让 ChainSystem 做“交互去重”
# ------------------------------------------------------------
func on_chain_hit(_player: Node, slot: int) -> int:
	if state != State.IDLE_IN_WORLD:
		return 0

	var p: Player = _player as Player
	if p == null:
		return 0

	var accepted := _start_acquire(p, slot, true)
	return 1 if accepted else 0


# ------------------------------------------------------------
# 吸附开始
# 说明：这里会向 Player 申请“携带槽位”，并获得 orbit_index(0/1)
# ------------------------------------------------------------
func _start_acquire(p: Player, preferred_slot: int, by_chain_hit: bool) -> bool:
	var idx: int = -1

	if p.has_method("try_collect_healing_sprite"):
		# ✅ 兼容：如果你的 Player 还没改成带 preferred_slot，这里先尝试2参，失败再回退1参
		var v = p.callv("try_collect_healing_sprite", [self, preferred_slot])
		if v == null:
			v = p.callv("try_collect_healing_sprite", [self])
		if v != null:
			idx = int(v)

	if idx < 0:
		# 满携带：不删除，不绑定 player（保持在场景里）
		return false

	player = p
	orbit_index = idx
	state = State.ACQUIRE

	acquire_timer = 0.0
	velocity = Vector2.ZERO

	var c: Vector2 = _get_orbit_center()
	_center_smoothed = c

	_init_individual_variation()

	# 锁链命中更跟手：跳过延迟
	if by_chain_hit and chain_hit_instant:
		acquire_timer = acquire_delay

	return true


func _init_individual_variation() -> void:
	var rng := RandomNumberGenerator.new()
	var seed_val: int = int(get_instance_id()) ^ (orbit_index * 1315423911)
	rng.seed = seed_val

	phase_jitter = rng.randf_range(-phase_jitter_max, phase_jitter_max)
	orbit_speed_mult = rng.randf_range(speed_mult_min, speed_mult_max)
	wobble_freq = rng.randf_range(wobble_freq_min, wobble_freq_max)
	wobble_phase = rng.randf_range(0.0, TAU)

	if use_opposite_orbit_dir:
		orbit_dir = -1.0 if orbit_index == 1 else 1.0
	else:
		orbit_dir = 1.0

	# 目标相位：两只大致错开 PI，再加微扰；通过平滑收敛避免“瞬移到固定点”
	phase_offset = 0.0
	phase_target = float(orbit_index) * PI + phase_jitter


# ------------------------------------------------------------
# 取得环绕中心：优先 Player.get_healing_orbit_center_global（你做的 Visual/center）
# ------------------------------------------------------------
func _get_orbit_center() -> Vector2:
	if player != null and is_instance_valid(player):
		# ✅ 新版：按槽位取不同center
		if player.has_method("get_healing_orbit_center_global"):
			var v = player.call("get_healing_orbit_center_global", orbit_index)
			if v is Vector2:
				return v
		return player.global_position
	return global_position
# ------------------------------------------------------------
# center.y 平滑：实现“跳跃滞后”
# ------------------------------------------------------------
func _smooth_center(dt: float, target_center: Vector2) -> Vector2:
	var tau: float = maxf(vertical_lag_time, 0.0001)
	var k: float = 1.0 - exp(-dt / tau)

	_center_smoothed.x = target_center.x
	_center_smoothed.y = lerpf(_center_smoothed.y, target_center.y, k)
	return _center_smoothed


# ------------------------------------------------------------
# 计算当前轨道相位（平滑相位分离 + 速度/摆动微差异）
# ------------------------------------------------------------
func _step_orbit_phase(dt: float) -> float:
	# 相位收敛（不瞬移）
	var w: float = 1.0 - exp(-dt * maxf(phase_settle_speed, 0.001))
	phase_offset = lerp_angle(phase_offset, phase_target, w)

	# 角速度更新（个体倍率 + 可选方向）
	orbit_angle += orbit_speed * orbit_speed_mult * orbit_dir * dt

	# 微摆动避免同相重叠
	var wobble: float = sin(orbit_angle * wobble_freq + wobble_phase) * wobble_amp

	return orbit_angle + phase_offset + wobble


func _get_orbit_radii() -> Vector2:
	var rx: float = orbit_radius_x + (radius_delta_x_by_index if orbit_index == 1 else 0.0)
	var ry: float = orbit_radius_y + (radius_delta_y_by_index if orbit_index == 1 else 0.0)
	return Vector2(rx, ry)


# ------------------------------------------------------------
# 吸附阶段
# - attach_distance > 0：追中心点，接近后进入 ORBIT（锁轨）
# - attach_distance <= 0：永远追逐“环绕目标点”（你喜欢的漂移/滞后效果）
# ------------------------------------------------------------
func _update_acquire(dt: float) -> void:
	if player == null or not is_instance_valid(player):
		_reset_to_idle()
		return

	acquire_timer += dt
	if acquire_timer < acquire_delay:
		return

	var center: Vector2 = _smooth_center(dt, _get_orbit_center())

	# ✅ 追逐环绕目标点模式（attach_distance<=0）
	if attach_distance <= 0.0:
		var a: float = _step_orbit_phase(dt)
		var r := _get_orbit_radii()
		var target_pos := center + Vector2(cos(a) * r.x, sin(a) * r.y)

		_chase_to(dt, target_pos)
		_update_pseudo_3d(a)
		return

	# ✅ 传统模式：追中心点，接近后锁轨 ORBIT
	var to_center: Vector2 = center - global_position
	if to_center.length() <= attach_distance:
		if use_vanish_transition:
			_start_vanish_then_orbit(center)
		else:
			_start_orbit_from_current(center)
		return

	var dir: Vector2 = to_center.normalized()
	velocity += dir * acquire_accel * dt
	if velocity.length() > acquire_max_speed:
		velocity = velocity.normalized() * acquire_max_speed
	global_position += velocity * dt


func _chase_to(dt: float, target_pos: Vector2) -> void:
	var to_t: Vector2 = target_pos - global_position
	if to_t.length_squared() < 0.0001:
		return

	var dir: Vector2 = to_t.normalized()
	velocity += dir * orbit_chase_accel * dt

	if velocity.length() > orbit_chase_max_speed:
		velocity = velocity.normalized() * orbit_chase_max_speed

	# 阻尼（按帧率归一）
	var damp: float = pow(clampf(orbit_chase_damping, 0.0, 0.9999), dt * 60.0)
	velocity *= damp

	global_position += velocity * dt


func _reset_to_idle() -> void:
	state = State.IDLE_IN_WORLD
	player = null
	velocity = Vector2.ZERO
	acquire_timer = 0.0


# ------------------------------------------------------------
# 锁轨 ORBIT：用当前位置反推 orbit_angle，避免进ORBIT瞬移
# ------------------------------------------------------------
func _start_orbit_from_current(center: Vector2) -> void:
	state = State.ORBIT
	_center_smoothed = center
	velocity = Vector2.ZERO

	var r := _get_orbit_radii()
	var rx: float = maxf(r.x, 0.001)
	var ry: float = maxf(r.y, 0.001)

	var rel: Vector2 = global_position - center
	orbit_angle = atan2(rel.y / ry, rel.x / rx)

	# 进入ORBIT时仍沿用相位分离逻辑，但不会强制跳到固定点
	# phase_target 已在 _init_individual_variation() 设置


func _update_orbit(dt: float) -> void:
	if player == null or not is_instance_valid(player):
		queue_free()
		return

	var center: Vector2 = _smooth_center(dt, _get_orbit_center())
	var a: float = _step_orbit_phase(dt)

	var r := _get_orbit_radii()
	global_position = center + Vector2(cos(a) * r.x, sin(a) * r.y)

	_update_pseudo_3d(a)


func _update_pseudo_3d(a: float) -> void:
	var depth: float = sin(a)            # -1..1
	var t: float = (depth + 1.0) * 0.5   # 0..1

	if visual != null:
		visual.scale = Vector2.ONE * lerpf(scale_min, scale_max, t)

	# z_index 加 index，减少同深度闪排序
	z_index = (10 if depth > 0.0 else -10) + orbit_index


# ------------------------------------------------------------
# 可选：消失过渡 -> 进入 ORBIT（为Spine2D留替换点）
# ------------------------------------------------------------
func _start_vanish_then_orbit(center: Vector2) -> void:
	state = State.VANISH
	_center_smoothed = center

	# Spine2D 预留：visual.play_vanish(duration)
	if visual != null and visual.has_method("play_vanish"):
		visual.call("play_vanish", vanish_time)
		var tw0 := create_tween()
		tw0.tween_interval(vanish_time)
		tw0.tween_callback(func() -> void:
			_start_orbit_from_current(_center_smoothed)
			_restore_visual_after_vanish()
		)
		return

	_prepare_dissolve_material()

	var tw := create_tween()
	tw.set_trans(Tween.TRANS_SINE)
	tw.set_ease(Tween.EASE_IN)

	if _dissolve_mat != null:
		tw.tween_method(
			func(v: float) -> void:
				_dissolve_mat.set_shader_parameter(dissolve_param_name, v),
			0.0, 1.0, vanish_time
		)
	else:
		tw.tween_method(
			func(v: float) -> void:
				_set_visual_alpha(1.0 - v),
			0.0, 1.0, vanish_time
		)

	tw.tween_callback(func() -> void:
		_start_orbit_from_current(_center_smoothed)
		_restore_visual_after_vanish()
	)


func _prepare_dissolve_material() -> void:
	_dissolve_mat = null
	if vanish_shader == null:
		return
	if visual == null:
		return

	var ci := visual as CanvasItem
	if ci == null:
		return

	var sm := ShaderMaterial.new()
	sm.shader = vanish_shader
	sm.set_shader_parameter(dissolve_param_name, 0.0)
	ci.material = sm
	_dissolve_mat = sm


func _restore_visual_after_vanish() -> void:
	if _dissolve_mat != null:
		_dissolve_mat.set_shader_parameter(dissolve_param_name, 0.0)
	_set_visual_alpha(1.0)
	state = State.ORBIT


func _set_visual_alpha(a: float) -> void:
	if visual == null:
		return
	var ci := visual as CanvasItem
	if ci == null:
		return
	var c: Color = ci.modulate
	c.a = clampf(a, 0.0, 1.0)
	ci.modulate = c


# ------------------------------------------------------------
# 被 Player.use_healing_sprite 调用：消耗
# ------------------------------------------------------------
func consume() -> void:
	state = State.CONSUMED
	queue_free()
