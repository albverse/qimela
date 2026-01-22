extends CharacterBody2D

enum ChainState { IDLE, FLYING, STUCK, LINKED, DISSOLVING }

# =========================
# 节点路径（按你当前节点树默认）
# =========================
@export var visual_path: NodePath = ^"Visual"                 # 角色视觉节点（用于翻转）
@export var hand_l_path: NodePath = ^"Visual/HandL"           # 左手发射点
@export var hand_r_path: NodePath = ^"Visual/HandR"           # 右手发射点
@export var chain_line0_path: NodePath = ^"Chains/ChainLine0" # 锁链0的Line2D
@export var chain_line1_path: NodePath = ^"Chains/ChainLine1" # 锁链1的Line2D

# =========================
# 角色移动参数
# =========================
@export var move_speed: float = 260.0         # 水平移动速度
@export var jump_speed: float = 520.0         # 跳跃初速度
@export var gravity: float = 1500.0           # 重力
@export var facing_visual_sign: float = 1.0   # 左右反了就改成 -1.0

# =========================
# 输入映射名（有就用，没有就读按键）
# 你要求：W跳跃（不再空格）
# =========================
@export var action_left: StringName = &"move_left"   # A
@export var action_right: StringName = &"move_right" # D
@export var action_jump: StringName = &"jump"        # W

# =========================
# 锁链行为参数
# =========================
@export var chain_speed: float = 1200.0        # 钩子飞行速度
@export var chain_max_length: float = 550.0    # 最大拉伸长度（越界触发溶解）
@export var chain_max_fly_time: float = 0.2    # 飞行超过就停住
@export var hold_time: float = 0.3            # 停住后悬停多久开始溶解
@export var burn_time: float = 1.0             # 溶解动画时长
@export var chain_shader_path: String = "res://shaders/chain_sand_dissolve.gdshader" # 散沙溶解shader
@export_flags_2d_physics var chain_hit_mask: int = 1

# =========================
# Rope视觉（Verlet + 波动叠加）
# =========================
@export var rope_segments: int = 22            # 绳子点数量（越大更细腻，但更耗）
@export var rope_damping: float = 0.88         # 阻尼（越小越“软/抖”，但更容易发散）
@export var rope_stiffness: float = 1.7        # 刚性（越大越绷直，抖动更局部）
@export var rope_iterations: int = 13          # 约束迭代（越大越稳定）
@export var rope_gravity: float = 0.0          # 绳子自重（想更“垂”就设 8~25）

# =========================
# “自然抖动”参数（你要的核心）
# 效果：整根绳都会抖，钩子附近最大，并快速恢复
# =========================
@export var rope_wave_amp: float = 44.0             # 发射瞬间的抖动幅度（像素级）
@export var rope_wave_freq: float = 10.0            # 波动频率（越大越快抖）
@export var rope_wave_decay: float = 7.5            # 衰减速度（越大越快稳定）
@export var rope_wave_hook_power: float = 2.2       # 钩子端权重（越大越集中在钩子）
@export var rope_wave_along_segments: float = 8.0   # 沿绳传播次数（越大波纹更多）

# 额外：端点移动也会激发全绳惯性（更自然）
@export var end_motion_inject: float = 0.5          # 钩子端运动注入力
@export var hand_motion_inject: float = 0.15        # 手端运动注入力

# =========================
# 断裂预警：越接近最大长度越红
# =========================
@export var warn_start_ratio: float = 0.80
@export var warn_gamma: float = 1.6
@export var warn_color: Color = Color(1.0, 0.259, 0.475, 1.0)

# =========================
# 材质展开端点控制：
# true：UV从钩子端开始 -> 缩进/展开只发生在手端（自然）
# =========================
@export var texture_anchor_at_hook: bool = true


# -------------------------
# 运行时引用
# -------------------------
var visual: Node2D
var hand_l: Node2D
var hand_r: Node2D
var facing: int = 1

var _burn_shader: Shader = null


class ChainSlot:
	var state: int = ChainState.IDLE
	var use_right_hand: bool = true
	var line: Line2D

	var end_pos: Vector2 = Vector2.ZERO
	var end_vel: Vector2 = Vector2.ZERO
	var fly_t: float = 0.0
	var hold_t: float = 0.0
	var linked_target: Node2D = null
	var linked_offset: Vector2 = Vector2.ZERO

	# rope buffers（世界坐标）
	var pts: PackedVector2Array = PackedVector2Array()
	var prev: PackedVector2Array = PackedVector2Array()

	# 用于“端点运动注入”
	var prev_end: Vector2 = Vector2.ZERO
	var prev_start: Vector2 = Vector2.ZERO

	# 用于“整绳抖动”的波参数
	var wave_amp: float = 0.0
	var wave_phase: float = 0.0
	var wave_seed: float = 0.0

	# 性能：缓存 RayQuery（避免每帧 create/new）
	var ray_q: PhysicsRayQueryParameters2D

	# 性能：每条链预创建溶解材质（避免反复 new ShaderMaterial）
	var burn_mat: ShaderMaterial
	var burn_tw: Tween

	# 性能：缓存权重表（避免每帧 pow）
	var w_end: PackedFloat32Array = PackedFloat32Array()
	var w_start: PackedFloat32Array = PackedFloat32Array()

	# 用于检测是否需要重建缓存
	var cached_n: int = -1
	var cached_hook_power: float = -999.0


var chains: Array[ChainSlot] = []


func _ready() -> void:
	visual = get_node_or_null(visual_path) as Node2D
	hand_l = get_node_or_null(hand_l_path) as Node2D
	hand_r = get_node_or_null(hand_r_path) as Node2D

	var line0: Line2D = get_node_or_null(chain_line0_path) as Line2D
	var line1: Line2D = get_node_or_null(chain_line1_path) as Line2D

	if visual == null or hand_l == null or hand_r == null:
		push_error("Player: visual/hand paths not set correctly.")
		set_process(false); set_physics_process(false)
		return

	if line0 == null or line1 == null:
		push_error("Player: chain line paths not set correctly.")
		set_process(false); set_physics_process(false)
		return

	_burn_shader = load(chain_shader_path) as Shader
	if _burn_shader == null:
		push_error("Player: cannot load chain shader: %s" % chain_shader_path)

	chains.clear()
	chains.resize(2)

	var c0 := ChainSlot.new()
	c0.use_right_hand = true
	c0.line = line0
	c0.wave_seed = 0.37
	_setup_chain_slot(c0)
	chains[0] = c0

	var c1 := ChainSlot.new()
	c1.use_right_hand = false
	c1.line = line1
	c1.wave_seed = 0.81
	_setup_chain_slot(c1)
	chains[1] = c1


func _setup_chain_slot(c: ChainSlot) -> void:
	_init_line(c.line)
	_init_rope_buffers(c)
	_prealloc_line_points(c)
	_rebuild_weight_cache_if_needed(c)

	# RayQuery 缓存
	c.ray_q = PhysicsRayQueryParameters2D.new()
	c.ray_q.collide_with_areas = true
	c.ray_q.collide_with_bodies = true
	c.ray_q.exclude = [self.get_rid()]
	c.ray_q.collision_mask = chain_hit_mask

	# 溶解材质预创建（每条链一份，避免串台）
	if _burn_shader != null:
		c.burn_mat = ShaderMaterial.new()
		c.burn_mat.shader = _burn_shader
	else:
		c.burn_mat = null


func _init_line(l: Line2D) -> void:
	l.visible = false
	l.material = null
	l.modulate = Color.WHITE


func _init_rope_buffers(c: ChainSlot) -> void:
	var n: int = max(rope_segments + 1, 2)
	c.pts.resize(n)
	c.prev.resize(n)
	for i in range(n):
		c.pts[i] = global_position
		c.prev[i] = global_position
	c.prev_end = global_position
	c.prev_start = global_position


# 关键优化：Line2D 点只分配一次，之后每帧 set_point_position
func _prealloc_line_points(c: ChainSlot) -> void:
	var n: int = c.pts.size()
	if c.line.get_point_count() != n:
		c.line.clear_points()
		for _i in range(n):
			c.line.add_point(Vector2.ZERO)


func _rebuild_weight_cache_if_needed(c: ChainSlot) -> void:
	var n: int = c.pts.size()
	if c.cached_n == n and is_equal_approx(c.cached_hook_power, rope_wave_hook_power):
		return

	c.cached_n = n
	c.cached_hook_power = rope_wave_hook_power

	c.w_end.resize(n)
	c.w_start.resize(n)

	if n <= 1:
		return

	var inv: float = 1.0 / float(n - 1)
	for k in range(n):
		var t: float = float(k) * inv # 0=手端, 1=钩子端
		c.w_end[k] = pow(t, rope_wave_hook_power)
		c.w_start[k] = pow(1.0 - t, 1.6)


func _physics_process(dt: float) -> void:
	_update_facing()

	# 左右：优先InputMap，否则读A/D
	var dir_x: float = 0.0
	if _has_action(action_left):
		if Input.is_action_pressed(action_left): dir_x -= 1.0
	else:
		if Input.is_key_pressed(KEY_A): dir_x -= 1.0

	if _has_action(action_right):
		if Input.is_action_pressed(action_right): dir_x += 1.0
	else:
		if Input.is_key_pressed(KEY_D): dir_x += 1.0

	velocity.x = dir_x * move_speed
	velocity.y += gravity * dt

	# 跳跃：W（不再空格）
	var jump_pressed: bool = false
	if _has_action(action_jump):
		jump_pressed = Input.is_action_just_pressed(action_jump)
	else:
		jump_pressed = Input.is_key_pressed(KEY_W)

	if is_on_floor() and jump_pressed:
		velocity.y = -jump_speed

	move_and_slide()

	for i in range(chains.size()):
		_update_chain(i, dt)


func _unhandled_input(event: InputEvent) -> void:
	# ✅ X 功能不需要：这里不处理 KEY_X

	# ✅ 鼠标左键发射（不依赖 shoot_chain）
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_try_fire_chain()


func _has_action(a: StringName) -> bool:
	return InputMap.has_action(a)


func _update_facing() -> void:
	var left: bool = false
	var right: bool = false

	if _has_action(action_left):
		left = Input.is_action_pressed(action_left)
	else:
		left = Input.is_key_pressed(KEY_A)

	if _has_action(action_right):
		right = Input.is_action_pressed(action_right)
	else:
		right = Input.is_key_pressed(KEY_D)

	if right and not left:
		facing = 1
	elif left and not right:
		facing = -1

	if visual != null:
		visual.scale.x = float(facing) * facing_visual_sign


func _try_fire_chain() -> void:
	if chains.size() < 2:
		return

	var idx: int = -1
	if chains[0].state == ChainState.IDLE:
		idx = 0
	elif chains[1].state == ChainState.IDLE:
		idx = 1
	else:
		return

	var c := chains[idx]
	var start: Vector2 = (hand_r.global_position if c.use_right_hand else hand_l.global_position)
	var target: Vector2 = get_global_mouse_position()

	var dir: Vector2 = target - start
	if dir.length() < 0.001:
		dir = Vector2(float(facing), 0.0)
	else:
		dir = dir.normalized()

	# segments 可能被你改过：确保缓冲和Line2D点数一致
	_init_rope_buffers(c)
	_prealloc_line_points(c)
	_rebuild_weight_cache_if_needed(c)

	c.state = ChainState.FLYING
	c.end_pos = start
	c.end_vel = dir * chain_speed
	c.fly_t = 0.0
	c.hold_t = 0.0
	c.linked_target = null
	c.linked_offset = Vector2.ZERO

	# 发射时给一发“整绳抖动能量”
	c.wave_amp = rope_wave_amp
	c.wave_phase = 0.0

	c.line.visible = true
	c.line.material = null
	c.line.modulate = Color.WHITE

	_reset_rope_line(c, start, c.end_pos)
	c.prev_start = start
	c.prev_end = c.end_pos


func _update_chain(i: int, dt: float) -> void:
	if i < 0 or i >= chains.size():
		return

	var c := chains[i]
	if c.state == ChainState.IDLE:
		return

	var start: Vector2 = (hand_r.global_position if c.use_right_hand else hand_l.global_position)

	# 越接近最大长度越红（非溶解时）
	if c.state != ChainState.DISSOLVING:
		_apply_break_warning_color(c, start)

	# 超长：触发溶解
	if start.distance_to(c.end_pos) > chain_max_length and c.state != ChainState.DISSOLVING:
		_begin_burn_dissolve(i)
		return

	match c.state:
		ChainState.FLYING:
			_update_chain_flying(i, dt)
		ChainState.STUCK:
			c.hold_t += dt
			if c.hold_t >= hold_time:
				_begin_burn_dissolve(i)
		ChainState.LINKED:
			if not _sync_linked_target(c):
				_begin_burn_dissolve(i)
		ChainState.DISSOLVING:
			pass

	_sim_rope(c, start, c.end_pos, dt)
	_apply_rope_to_line_fast(c)


func _apply_break_warning_color(c: ChainSlot, start: Vector2) -> void:
	var d: float = start.distance_to(c.end_pos)
	var r: float = clamp(d / chain_max_length, 0.0, 1.0)

	if r <= warn_start_ratio:
		c.line.modulate = Color.WHITE
		return

	var t: float = (r - warn_start_ratio) / maxf(1.0 - warn_start_ratio, 0.0001)
	t = pow(t, warn_gamma)
	c.line.modulate = Color.WHITE.lerp(warn_color, t)


func _update_chain_flying(i: int, dt: float) -> void:
	var c := chains[i]

	var prev_pos: Vector2 = c.end_pos
	c.end_pos = c.end_pos + c.end_vel * dt
	c.fly_t += dt

	# Raycast（复用 Query）
	var space := get_world_2d().direct_space_state
	c.ray_q.from = prev_pos
	c.ray_q.to = c.end_pos

	var hit: Dictionary = space.intersect_ray(c.ray_q)
	if hit.size() > 0:
		c.end_pos = hit["position"] as Vector2
		if _handle_chain_hit(i, hit):
			return

		c.state = ChainState.STUCK
		c.hold_t = 0.0
		# 命中瞬间余震
		c.wave_amp = maxf(c.wave_amp, rope_wave_amp * 0.6)
		return

	# 超时未命中：停住
	if c.fly_t >= chain_max_fly_time:
		c.state = ChainState.STUCK
		c.hold_t = 0.0
		c.wave_amp = maxf(c.wave_amp, rope_wave_amp * 0.35)


func _begin_burn_dissolve(i: int) -> void:
	if i < 0 or i >= chains.size():
		return

	var c := chains[i]
	if c.state == ChainState.DISSOLVING or c.state == ChainState.IDLE:
		return

	if c.burn_mat == null:
		_finish_chain(i)
		return

	# 如果上一轮 tween 还在，先杀掉（避免参数串）
	if c.burn_tw != null:
		c.burn_tw.kill()
		c.burn_tw = null

	c.line.material = c.burn_mat
	c.burn_mat.set_shader_parameter("burn", 0.0)
	c.state = ChainState.DISSOLVING

	var tw := create_tween()
	c.burn_tw = tw
	tw.set_trans(Tween.TRANS_SINE)
	tw.set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(c.burn_mat, "shader_parameter/burn", 1.0, burn_time)
	tw.tween_callback(func() -> void:
		_finish_chain(i)
	)


func _finish_chain(i: int) -> void:
	if i < 0 or i >= chains.size():
		return
	var c := chains[i]

	if c.linked_target != null and is_instance_valid(c.linked_target):
		if c.linked_target.has_method("on_chain_unlinked"):
			c.linked_target.call("on_chain_unlinked")
	c.linked_target = null
	c.linked_offset = Vector2.ZERO

	if c.burn_tw != null:
		c.burn_tw.kill()
		c.burn_tw = null

	c.state = ChainState.IDLE
	c.line.visible = false
	c.line.material = null
	c.line.modulate = Color.WHITE
	c.wave_amp = 0.0
	c.wave_phase = 0.0


func _handle_chain_hit(i: int, hit: Dictionary) -> bool:
	var c := chains[i]
	var collider := hit.get("collider")
	var hit_pos: Vector2 = hit.get("position", c.end_pos)

	if collider is Node and (collider as Node).has_method("on_chain_hit"):
		var result = (collider as Node).call("on_chain_hit", hit_pos, self)
		if result is Dictionary:
			var action: String = result.get("action", "")
			if action == "link":
				var target: Node2D = result.get("target", null)
				if target != null and is_instance_valid(target):
					c.state = ChainState.LINKED
					c.linked_target = target
					c.linked_offset = hit_pos - target.global_position
					c.end_pos = target.global_position + c.linked_offset
					c.wave_amp = maxf(c.wave_amp, rope_wave_amp * 0.6)
					if target.has_method("on_chain_linked"):
						target.call("on_chain_linked", self)
					return true
			if action == "dissolve":
				_begin_burn_dissolve(i)
				return true

	return false


func _sync_linked_target(c: ChainSlot) -> bool:
	if c.linked_target == null or not is_instance_valid(c.linked_target):
		return false
	c.end_pos = c.linked_target.global_position + c.linked_offset
	return true


# =========================
# Rope：Verlet + 端点注入 + 波动（快速衰减）
# =========================
func _reset_rope_line(c: ChainSlot, start_world: Vector2, end_world: Vector2) -> void:
	var n: int = c.pts.size()
	if n < 2:
		return
	for k in range(n):
		var t: float = float(k) / float(n - 1)
		var p: Vector2 = start_world.lerp(end_world, t)
		c.pts[k] = p
		c.prev[k] = p


func _sim_rope(c: ChainSlot, start_world: Vector2, end_world: Vector2, dt: float) -> void:
	var n: int = c.pts.size()
	if n < 2:
		return
	var last: int = n - 1

	# 端点锁定
	c.pts[0] = start_world
	c.pts[last] = end_world

	# 端点位移（用于整绳惯性注入）
	var start_delta: Vector2 = start_world - c.prev_start
	var end_delta: Vector2 = end_world - c.prev_end
	c.prev_start = start_world
	c.prev_end = end_world

	# Verlet 积分
	for k in range(1, last):
		var cur: Vector2 = c.pts[k]
		var vel: Vector2 = (cur - c.prev[k]) * rope_damping
		c.prev[k] = cur
		c.pts[k] = cur + vel + Vector2(0.0, rope_gravity)

	# 端点运动注入（使用缓存权重）
	_rebuild_weight_cache_if_needed(c)
	for k in range(1, last):
		var w_end: float = c.w_end[k]
		var w_start: float = c.w_start[k]
		c.pts[k] += end_delta * (end_motion_inject * w_end)
		c.pts[k] += start_delta * (hand_motion_inject * w_start)

	# 波动叠加（快速衰减）：整根抖动，钩子端更强
	if c.wave_amp > 0.001:
		c.wave_amp *= exp(-rope_wave_decay * dt)
		c.wave_phase += (rope_wave_freq * TAU) * dt

		# 波动方向：沿绳垂直方向
		var dir: Vector2 = end_world - start_world
		var perp: Vector2 = Vector2(-dir.y, dir.x)
		if perp.length() < 0.001:
			perp = Vector2.UP
		else:
			perp = perp.normalized()

		for k in range(1, last):
			var t2: float = float(k) / float(last) # 0=手 1=钩
			var w: float = c.w_end[k]              # 直接复用钩子权重
			var phase: float = c.wave_phase + (t2 * rope_wave_along_segments * TAU) + c.wave_seed * 10.0
			c.pts[k] += perp * (sin(phase) * c.wave_amp * w)

	# 约束：保持段长（稳定回正）
	var total_len: float = start_world.distance_to(end_world)
	var seg_len: float = total_len / float(last)

	for _it in range(rope_iterations):
		c.pts[0] = start_world
		c.pts[last] = end_world

		for k in range(last):
			var a: Vector2 = c.pts[k]
			var b: Vector2 = c.pts[k + 1]
			var delta: Vector2 = b - a
			var d: float = maxf(delta.length(), 0.0001)
			var diff: float = (d - seg_len) / d
			var adj: Vector2 = delta * (0.5 * rope_stiffness * diff)

			if k != 0:
				c.pts[k] += adj
			if k + 1 != last:
				c.pts[k + 1] -= adj


# 关键优化：不再 clear/add，每帧只 set_point_position
# 同时保持“texture_anchor_at_hook=true 时 UV锚在钩子端 -> 展开只发生在手端”
func _apply_rope_to_line_fast(c: ChainSlot) -> void:
	var n: int = c.pts.size()
	if c.line.get_point_count() != n:
		_prealloc_line_points(c)

	if texture_anchor_at_hook:
		# Line点序固定 0..n-1，但数据源用反向 pts（让UV从钩子端起）
		for i in range(n):
			var src: int = (n - 1) - i
			c.line.set_point_position(i, c.line.to_local(c.pts[src]))
	else:
		for i in range(n):
			c.line.set_point_position(i, c.line.to_local(c.pts[i]))
