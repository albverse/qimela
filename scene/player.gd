extends CharacterBody2D
# Godot 4.5  |  数据A（稳定基线 + 融合/奇美拉A框架 + 物理层/Mask可配置）
# 目标：
# - 鼠标左键发射锁链；W 跳跃；A/D 左右
# - 锁链命中普通怪物：掉血/受击/僵直，锁链立刻溶解
# - 怪物虚弱（HP==1）后再命中：锁链进入 LINKED（不再按 hold_time 自动溶解），超出最大长度才断
# - 两根锁链分别 LINKED 两只虚弱怪物：按空格融合 -> 0.5s 演出 -> 生成 ChimeraA
# - Rope 视觉：Verlet + “整绳抖动（钩子端更强，快速恢复）”
#
# 重要：
# - 本文件内的 @export 都保留并注释用途，方便你调参。
# - 不包含 X 立即取消功能（你已明确暂时不需要）。

enum ChainState { IDLE, FLYING, STUCK, LINKED, DISSOLVING }

# =========================
# 节点路径（按你当前节点树默认）
# =========================
@export var visual_path: NodePath = ^"Visual"                 # 角色视觉节点（用于翻转）
@export var hand_l_path: NodePath = ^"Visual/HandL"           # 左手发射点
@export var hand_r_path: NodePath = ^"Visual/HandR"           # 右手发射点
@export var chain_line0_path: NodePath = ^"Chains/ChainLine0" # 锁链0的 Line2D
@export var chain_line1_path: NodePath = ^"Chains/ChainLine1" # 锁链1的 Line2D

# =========================
# 输入映射名（有就用，没有就读按键）
# =========================
@export var action_left: StringName = &"move_left"    # A
@export var action_right: StringName = &"move_right"  # D
@export var action_jump: StringName = &"jump"         # W（你要 W 跳跃）
@export var action_fuse: StringName = &"fuse"         # 空格：融合（可选 InputMap）

# =========================
# 角色移动参数
# =========================
@export var move_speed: float = 260.0         # 水平移动速度
@export var jump_speed: float = 520.0         # 跳跃初速度
@export var gravity: float = 1500.0           # 重力
@export var facing_visual_sign: float = 1.0   # 角色左右反了就改成 -1.0（只翻 Visual）

# =========================
# 锁链行为参数
# =========================
@export var chain_speed: float = 1200.0        # 钩子飞行速度（像子弹一样推进）
@export var chain_max_length: float = 550.0    # 最大拉伸长度（超过触发溶解/断裂）
@export var chain_max_fly_time: float = 0.2    # 飞行超过就 STUCK（未命中也会停住）
@export var hold_time: float = 0.3             # STUCK 后悬停多久开始溶解
@export var burn_time: float = 1.0             # 溶解动画时长（shader burn 0->1）
@export var fusion_lock_time: float = 0.5      # 融合演出期间锁玩家（不能移动）
@export var fusion_chain_dissolve_time: float = 0.5 # 融合时两条链溶解用时（更快）

@export var chain_shader_path: String = "res://shaders/chain_sand_dissolve.gdshader" # 散沙溶解 shader 路径

# 锁链射线“命中哪些层”
# ✅ 这里就是你问的 chain_hit_mask：Inspector 会出现勾选框（World / EnemyHurtbox / ...）
@export_flags_2d_physics var chain_hit_mask: int = 0

# =========================
# Rope 视觉（Verlet + 波动叠加）
# =========================
@export var rope_segments: int = 22            # 绳子点数量（越大更细腻，但更耗）
@export var rope_damping: float = 0.88         # 阻尼（越小越“软/抖”，但更容易发散）
@export var rope_stiffness: float = 1.7        # 刚性（越大越绷直，抖动更局部）
@export var rope_iterations: int = 13          # 约束迭代（越大越稳定）
@export var rope_gravity: float = 0.0          # 绳子自重（想更“垂”就设 8~25）

# =========================
# “自然抖动”参数（核心）
# 效果：整根绳都会抖，钩子端抖最大，并快速恢复
# =========================
@export var rope_wave_amp: float = 44.0             # 发射瞬间的抖动幅度（像素级）
@export var rope_wave_freq: float = 10.0            # 波动频率（越大越快抖）
@export var rope_wave_decay: float = 7.5            # 衰减速度（越大越快稳定）
@export var rope_wave_hook_power: float = 2.2       # 钩子端权重（越大越集中在钩子）
@export var rope_wave_along_segments: float = 8.0   # 沿绳传播次数（越大波纹更多）

# 端点移动也会激发全绳惯性（更自然）
@export var end_motion_inject: float = 0.5          # 钩子端运动注入力
@export var hand_motion_inject: float = 0.15        # 手端运动注入力

# =========================
# 断裂预警：越接近最大长度越红
# =========================
@export var warn_start_ratio: float = 0.80          # 从最大长度的多少比例开始变红
@export var warn_gamma: float = 1.6                 # 红色渐变曲线（>1 更靠近末端才急剧变红）
@export var warn_color: Color = Color(1.0, 0.259, 0.475, 1.0)  # 预警红色

# =========================
# 材质展开端点控制：
# true：UV 从钩子端开始 -> 缩进/展开只发生在手端（自然）
# =========================
@export var texture_anchor_at_hook: bool = true

# =========================
# 奇美拉生成
# =========================
@export var chimeraA_scene: PackedScene                 # 指向 ChimeraA.tscn（在 Inspector 拖）
@export_flags_2d_physics var chimera_spawn_block_mask: int = 0  # 用于找“不会卡住”的生成点（通常只勾 World）
@export var chimera_spawn_radius: float = 10.0          # 生成点的简单“避障”半径（越大越保守）
@export var chimera_spawn_try_step: float = 18.0        # 每次尝试往上/两侧挪多少像素
@export var chimera_spawn_disable_collision_frames: int = 1  # 生成后禁碰撞几帧（双保险）

# -------------------------
# 运行时引用
# -------------------------
var visual: Node2D
var hand_l: Node2D
var hand_r: Node2D
var facing: int = 1

var _burn_shader: Shader = null
var _player_locked: bool = false

class ChainSlot:
	var state: int = ChainState.IDLE
	var use_right_hand: bool = true
	var line: Line2D

	var end_pos: Vector2 = Vector2.ZERO
	var end_vel: Vector2 = Vector2.ZERO
	var fly_t: float = 0.0
	var hold_t: float = 0.0

	# rope buffers（世界坐标）
	var pts: PackedVector2Array = PackedVector2Array()
	var prev: PackedVector2Array = PackedVector2Array()
	var prev_end: Vector2 = Vector2.ZERO
	var prev_start: Vector2 = Vector2.ZERO

	# 波动参数
	var wave_amp: float = 0.0
	var wave_phase: float = 0.0
	var wave_seed: float = 0.0

	# 性能：缓存 RayQuery
	var ray_q: PhysicsRayQueryParameters2D
	# 性能：每条链一份材质（避免串台）
	var burn_mat: ShaderMaterial
	var burn_tw: Tween

	# 性能：缓存权重表（避免每帧 pow）
	var w_end: PackedFloat32Array = PackedFloat32Array()
	var w_start: PackedFloat32Array = PackedFloat32Array()
	var cached_n: int = -1
	var cached_hook_power: float = -999.0

	# LINKED 目标
	var linked_target: Node2D = null
	var linked_offset: Vector2 = Vector2.ZERO  # 命中点相对目标的偏移（保持挂点）

var chains: Array[ChainSlot] = []

# =========================
# 生命周期
# =========================
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

	# 默认命中层（如果你没在 Inspector 勾）
	# 建议：1=World, 4=EnemyHurtbox（你自己按工程设置改）
	if chain_hit_mask == 0:
		chain_hit_mask = (1 << 0) | (1 << 3) # 默认勾第1层 + 第4层

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

	# 溶解材质：每条链一份（避免上一条链的 burn 残留）
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

	# 移动
	if not _player_locked:
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
	else:
		velocity.x = 0.0

	velocity.y += gravity * dt

	# 跳跃：W
	var jump_pressed: bool = false
	if not _player_locked:
		if _has_action(action_jump):
			jump_pressed = Input.is_action_just_pressed(action_jump)
		else:
			jump_pressed = Input.is_key_pressed(KEY_W)

	if not _player_locked and is_on_floor() and jump_pressed:
		velocity.y = -jump_speed

	move_and_slide()

	# 更新两条锁链
	for i in range(chains.size()):
		_update_chain(i, dt)


func _unhandled_input(event: InputEvent) -> void:
	# 鼠标左键：发射锁链
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_try_fire_chain()
			return

	# 空格：融合（优先 InputMap，没有就读 Space）
	if event is InputEventKey:
		var ek := event as InputEventKey
		if not ek.pressed:
			return

		var fuse_pressed: bool = false
		if _has_action(action_fuse):
			fuse_pressed = Input.is_action_just_pressed(action_fuse)
		else:
			fuse_pressed = (ek.keycode == KEY_SPACE)

		if fuse_pressed:
			_try_fuse()
			return


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


# =========================
# 发射锁链
# =========================
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

	# 确保点数一致
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


# =========================
# 每帧更新锁链
# =========================
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

	# 超长：触发溶解/断裂
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
			if c.linked_target == null or not is_instance_valid(c.linked_target):
				_begin_burn_dissolve(i)
				return
			# 端点固定在目标身上的“挂点”
			c.end_pos = c.linked_target.global_position + c.linked_offset
			# 超过最大长度：断裂消失
			if start.distance_to(c.end_pos) > chain_max_length:
				_begin_burn_dissolve(i)
				return
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


# =========================
# FLYING：射线命中
# =========================
func _update_chain_flying(i: int, dt: float) -> void:
	var c := chains[i]

	var prev_pos: Vector2 = c.end_pos
	var next_pos: Vector2 = c.end_pos + c.end_vel * dt
	c.end_pos = next_pos
	c.fly_t += dt

	# Raycast（复用 Query）
	var space := get_world_2d().direct_space_state
	c.ray_q.from = prev_pos
	c.ray_q.to = c.end_pos
	c.ray_q.collision_mask = chain_hit_mask

	var hit: Dictionary = space.intersect_ray(c.ray_q)
	
	if hit.size() > 0:
		var hit_pos: Vector2 = hit.get("position", c.end_pos) as Vector2
		c.end_pos = hit_pos
		var col_obj: Object = hit.get("collider", null) as Object
		var col_node: Node = col_obj as Node
		# 命中瞬间余震
		c.wave_amp = maxf(c.wave_amp, rope_wave_amp * 0.6)

		# 命中 EnemyHurtbox：解析逻辑主体并走统一接口
		var hurtbox: EnemyHurtbox = col_node as EnemyHurtbox
		if hurtbox != null:
			var host: Node = hurtbox.get_host()
			if host != null and host.has_method("on_chain_hit"):
				# 约定返回值：0=普通受击并溶解；1=进入 LINKED；2=忽略/穿透
				var ret: int = int(host.call("on_chain_hit", self, i, c.end_pos))
				if ret == 1:
					_chain_enter_linked(i, host, c.end_pos)
					return
				if ret == 2:
					c.end_pos = next_pos
					return
				_begin_burn_dissolve(i)
				return

			# Hurtbox 没有宿主：直接溶解
			_begin_burn_dissolve(i)
			return

		# Hurtbox 没有宿主：直接溶解
		_begin_burn_dissolve(i)
		return

	# 命中普通平台/静物：你要“停止/结束”，这里直接溶解
	_begin_burn_dissolve(i)
	return

	# 超时未命中：停住（悬停 hold_time 后溶解）
	if c.fly_t >= chain_max_fly_time:
		c.state = ChainState.STUCK
		c.hold_t = 0.0
		c.wave_amp = maxf(c.wave_amp, rope_wave_amp * 0.35)


func _chain_enter_linked(i: int, target: Node, hit_pos: Vector2) -> void:
	var c := chains[i]
	var t2d: Node2D = target as Node2D
	if t2d == null:
		_begin_burn_dissolve(i)
		return

	c.state = ChainState.LINKED
	c.linked_target = t2d
	c.linked_offset = hit_pos - t2d.global_position
	c.hold_t = 0.0

	# 通知目标：链已挂上（用于触发互动）
	if target.has_method("on_chain_attached"):
		target.call("on_chain_attached", i, self, hit_pos)


# =========================
# 溶解（shader burn）
# =========================
func _begin_burn_dissolve(i: int, dissolve_time: float = -1.0) -> void:
	if i < 0 or i >= chains.size():
		return

	var c := chains[i]
	if c.state == ChainState.DISSOLVING or c.state == ChainState.IDLE:
		return

	# 如果此前是 LINKED，先通知目标断开
	if c.state == ChainState.LINKED and c.linked_target != null and is_instance_valid(c.linked_target):
		if c.linked_target.has_method("on_chain_detached"):
			c.linked_target.call("on_chain_detached", i)
	c.linked_target = null
	c.linked_offset = Vector2.ZERO

	# 材质
	if c.burn_mat == null:
		# shader 不存在：直接结束
		_finish_chain(i)
		return

	# kill 旧 tween（避免 burn 串台）
	if c.burn_tw != null:
		c.burn_tw.kill()
		c.burn_tw = null

	c.line.material = c.burn_mat
	c.burn_mat.set_shader_parameter("burn", 0.0)

	c.state = ChainState.DISSOLVING

	var t: float = burn_time if dissolve_time <= 0.0 else dissolve_time

	var tw := create_tween()
	c.burn_tw = tw
	tw.set_trans(Tween.TRANS_SINE)
	tw.set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(c.burn_mat, "shader_parameter/burn", 1.0, t)
	tw.tween_callback(func() -> void:
		_finish_chain(i)
	)


func _finish_chain(i: int) -> void:
	if i < 0 or i >= chains.size():
		return

	var c := chains[i]

	if c.burn_tw != null:
		c.burn_tw.kill()
		c.burn_tw = null

	# 保险：若仍处于 LINKED，也通知断开
	if c.state == ChainState.LINKED and c.linked_target != null and is_instance_valid(c.linked_target):
		if c.linked_target.has_method("on_chain_detached"):
			c.linked_target.call("on_chain_detached", i)

	c.state = ChainState.IDLE
	c.line.visible = false
	c.line.material = null
	c.line.modulate = Color.WHITE
	c.wave_amp = 0.0
	c.wave_phase = 0.0
	c.linked_target = null
	c.linked_offset = Vector2.ZERO


# =========================
# 融合：两条链都 LINKED 两个“虚弱怪物”
# =========================
func _try_fuse() -> void: 
	var t0 := chains[0].linked_target
	var t1 := chains[1].linked_target
	print("[FUSE] type0=", (t0.get_class() if t0 else "null"),
		  " type1=", (t1.get_class() if t1 else "null"))
	if _player_locked:
		return
	if chains.size() < 2:
		return

	var c0 := chains[0]
	var c1 := chains[1]
	if c0.state != ChainState.LINKED or c1.state != ChainState.LINKED:
		return
	if c0.linked_target == null or c1.linked_target == null:
		return
	if c0.linked_target == c1.linked_target:
		return

	var m0: MonsterBase = c0.linked_target as MonsterBase
	var m1: MonsterBase = c1.linked_target as MonsterBase
	if m0 == null or m1 == null:
		return
	if not m0.weak or not m1.weak:
		return

	# ✅ 只先实现：MonsterFly + MonsterWalk => ChimeraA（顺序无关）
	var ok_pair: bool = _is_pair_for_chimeraA(m0, m1)
	if not ok_pair:
		# 先不做其它 Chimera，直接拒绝
		return

	_player_locked = true
	velocity = Vector2.ZERO

	# 怪物原地“消失”（禁碰撞+隐藏视觉）
	m0.set_fusion_vanish(true)
	m1.set_fusion_vanish(true)

	# 两条链更快溶解
	_begin_burn_dissolve(0, fusion_chain_dissolve_time)
	_begin_burn_dissolve(1, fusion_chain_dissolve_time)

	var tw := create_tween()
	tw.tween_interval(fusion_lock_time)
	tw.tween_callback(func() -> void:
		if is_instance_valid(m0): m0.queue_free()
		if is_instance_valid(m1): m1.queue_free()
		await _spawn_chimeraA_safe()
		_player_locked = false
	)


func _is_pair_for_chimeraA(a: MonsterBase, b: MonsterBase) -> bool:
	# 仅用于 ChimeraA：FLY + WALK
	var ka: int = int(a.kind)
	var kb: int = int(b.kind)
	return (ka == int(MonsterBase.MonsterKind.FLY) and kb == int(MonsterBase.MonsterKind.WALK)) \
		or (ka == int(MonsterBase.MonsterKind.WALK) and kb == int(MonsterBase.MonsterKind.FLY))


# A + B 双保险生成：A 找不重叠点，B 禁碰撞 1 帧再启用
func _spawn_chimeraA_safe() -> void:
	if chimeraA_scene == null:
		return

	var parent: Node = get_parent()
	if parent == null:
		return

	var origin: Vector2 = global_position
	var spawn_pos: Vector2 = _find_non_overlapping_spawn_pos(origin)

	var inst: Node = chimeraA_scene.instantiate()
	var n2d: Node2D = inst as Node2D
	if n2d == null:
		return

	n2d.global_position = spawn_pos
	parent.add_child(n2d)

	# 生成后：禁碰撞 N 帧（双保险）
	var co: CollisionObject2D = inst as CollisionObject2D
	var old_layer: int = 0
	var old_mask: int = 0
	if co != null:
		old_layer = int(co.collision_layer)
		old_mask = int(co.collision_mask)
		co.collision_layer = 0
		co.collision_mask = 0

	for _i in range(chimera_spawn_disable_collision_frames):
		await get_tree().physics_frame

	if co != null:
		co.collision_layer = old_layer
		co.collision_mask = old_mask

	# 告诉 ChimeraA 玩家引用（兼容 set_player / setup）
	if inst.has_method("set_player"):
		inst.call("set_player", self)
	elif inst.has_method("setup"):
		inst.call("setup", self)


# 用 PhysicsShapeQueryParameters2D 找不会卡住的生成点
func _find_non_overlapping_spawn_pos(origin: Vector2) -> Vector2:
	var space := get_world_2d().direct_space_state

	var shape := CircleShape2D.new()
	shape.radius = chimera_spawn_radius

	var qp: PhysicsShapeQueryParameters2D = PhysicsShapeQueryParameters2D.new()
	qp.shape = shape
	qp.collision_mask = chimera_spawn_block_mask if chimera_spawn_block_mask != 0 else (1 << 0) # 默认只挡 World
	qp.exclude = [self.get_rid()]
	qp.margin = 0.1

	# 依次尝试：上、右上、左上、右、左、再更上...
	var offsets: Array[Vector2] = []
	offsets.append(Vector2(0.0, -chimera_spawn_try_step))
	offsets.append(Vector2(chimera_spawn_try_step, -chimera_spawn_try_step))
	offsets.append(Vector2(-chimera_spawn_try_step, -chimera_spawn_try_step))
	offsets.append(Vector2(chimera_spawn_try_step, 0.0))
	offsets.append(Vector2(-chimera_spawn_try_step, 0.0))
	offsets.append(Vector2(0.0, -chimera_spawn_try_step * 2.0))
	offsets.append(Vector2(chimera_spawn_try_step, -chimera_spawn_try_step * 2.0))
	offsets.append(Vector2(-chimera_spawn_try_step, -chimera_spawn_try_step * 2.0))

	for off in offsets:
		var p: Vector2 = origin + off
		qp.transform = Transform2D(0.0, p)
		var hits: Array[Dictionary] = space.intersect_shape(qp, 1)
		if hits.is_empty():
			return p

	return origin


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

	# 波动叠加（快速衰减）
	if c.wave_amp > 0.001:
		c.wave_amp *= exp(-rope_wave_decay * dt)
		c.wave_phase += (rope_wave_freq * TAU) * dt

		var dir: Vector2 = end_world - start_world
		var perp: Vector2 = Vector2(-dir.y, dir.x)
		if perp.length() < 0.001:
			perp = Vector2.UP
		else:
			perp = perp.normalized()

		for k in range(1, last):
			var t2: float = float(k) / float(last) # 0=手 1=钩
			var w: float = c.w_end[k]              # 钩子端更强
			var phase: float = c.wave_phase + (t2 * rope_wave_along_segments * TAU) + c.wave_seed * 10.0
			c.pts[k] += perp * (sin(phase) * c.wave_amp * w)

	# 约束：保持段长
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


# 不再 clear/add，每帧 set_point_position；同时保留“UV锚在钩子端”
func _apply_rope_to_line_fast(c: ChainSlot) -> void:
	var n: int = c.pts.size()
	if c.line.get_point_count() != n:
		_prealloc_line_points(c)

	if texture_anchor_at_hook:
		for i in range(n):
			var src: int = (n - 1) - i
			c.line.set_point_position(i, c.line.to_local(c.pts[src]))
	else:
		for i in range(n):
			c.line.set_point_position(i, c.line.to_local(c.pts[i]))
