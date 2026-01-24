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
# 融合 / 生成
# =========================
@export var action_fuse: StringName = &"fuse"                 # 空格：融合（可选InputMap）
@export var action_cancel_chains: StringName = &"cancel_chains" # X：强制消失锁链
@export var fusion_lock_time: float = 0.5                     # 融合演出期间锁玩家
@export var fusion_chain_dissolve_time: float = 0.5           # 融合时两条链溶解用时（更快）
@export var chimera_scene: PackedScene                        # 指向 ChimeraA.tscn（你当前用这个即可）

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
@export var chain_max_length: float = 550.0    # 最大拉伸长度（越界触发溶解/断裂）
@export var chain_max_fly_time: float = 0.2    # 飞行超过就停住
@export var hold_time: float = 0.3             # 停住后悬停多久开始溶解
@export var burn_time: float = 1.0             # 溶解动画时长
@export var cancel_dissolve_time: float = 0.3  # 强制取消时的溶解时长
const DEFAULT_CHAIN_SHADER_PATH: String = "res://shaders/chain_sand_dissolve.gdshader"
@export var chain_shader_path: String = DEFAULT_CHAIN_SHADER_PATH # 散沙溶解shader

# 锁链射线命中层（在 Inspector 里以勾选框显示）。
# 你把 2D 物理层命名成 World / EnemyHurtbox 后，这里就能直接勾选。
@export_flags_2d_physics var chain_hit_mask: int = 0xFFFFFFFF

# =========================
# Rope视觉（Verlet + 波动叠加）
# =========================
@export var rope_segments: int = 22            # 绳子点数量（越大更细腻，但更耗）
@export var rope_damping: float = 0.88         # 阻尼
@export var rope_stiffness: float = 1.7        # 刚性
@export var rope_iterations: int = 13          # 约束迭代
@export var rope_gravity: float = 0.0          # 绳子自重

# =========================
# “自然抖动”参数
# =========================
@export var rope_wave_amp: float = 44.0
@export var rope_wave_freq: float = 10.0
@export var rope_wave_decay: float = 7.5
@export var rope_wave_hook_power: float = 2.2
@export var rope_wave_along_segments: float = 8.0

@export var end_motion_inject: float = 0.5
@export var hand_motion_inject: float = 0.15

# =========================
# 断裂预警：越接近最大长度越红
# =========================
@export var warn_start_ratio: float = 0.80
@export var warn_gamma: float = 1.6
@export var warn_color: Color = Color(1.0, 0.259, 0.475, 1.0)

# =========================
# 材质展开端点控制
# true：UV从钩子端开始 -> 缩进/展开只发生在手端（自然）
# =========================
@export var texture_anchor_at_hook: bool = true

# =========================
# Chimera 安全生成（A+B）
# =========================
@export var spawn_try_up_step: float = 16.0          # 每次向上试探的步长
@export var spawn_try_up_count: int = 10             # 向上试探次数
@export var spawn_try_side: float = 24.0             # 侧向偏移（左右各试）
@export var spawn_disable_collision_one_frame: bool = true  # B：禁碰撞1帧

# -------------------------
# 运行时引用
# -------------------------
var visual: Node2D
var hand_l: Node2D
var hand_r: Node2D
var facing: int = 1

var _burn_shader: Shader = null
var _player_locked: bool = false
var _chimera: Node = null


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

	# 用于“端点运动注入”
	var prev_end: Vector2 = Vector2.ZERO
	var prev_start: Vector2 = Vector2.ZERO

	# 波参数
	var wave_amp: float = 0.0
	var wave_phase: float = 0.0
	var wave_seed: float = 0.0

	# 性能：缓存 RayQuery
	var ray_q: PhysicsRayQueryParameters2D

	# 性能：每条链预创建溶解材质（避免串台）
	var burn_mat: ShaderMaterial
	var burn_tw: Tween

	# 性能：缓存权重表
	var w_end: PackedFloat32Array = PackedFloat32Array()
	var w_start: PackedFloat32Array = PackedFloat32Array()
	var cached_n: int = -1
	var cached_hook_power: float = -999.0

	# ✅ 链接对象（monster/chimera 都走这套）
	var linked_target: Node2D = null
	var linked_offset: Vector2 = Vector2.ZERO


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

	if chain_shader_path == "" or chain_shader_path == null:
		chain_shader_path = DEFAULT_CHAIN_SHADER_PATH
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
	c.ray_q.collision_mask = chain_hit_mask
	c.ray_q.exclude = [self.get_rid()]

	# 溶解材质预创建（每条链一份）
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
		var t: float = float(k) * inv
		c.w_end[k] = pow(t, rope_wave_hook_power)
		c.w_start[k] = pow(1.0 - t, 1.6)


func _physics_process(dt: float) -> void:
	_update_facing()

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
	if not _player_locked:
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
	# 鼠标左键：发射锁链
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_try_fire_chain()
			return

	# 空格：融合（优先InputMap，没有就读Space）
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

		# X：强制消失所有锁链
		var cancel_pressed: bool = false
		if _has_action(action_cancel_chains):
			cancel_pressed = Input.is_action_just_pressed(action_cancel_chains)
		else:
			cancel_pressed = (ek.keycode == KEY_X)

		if cancel_pressed:
			_force_dissolve_all_chains()
			return


func _has_action(a: StringName) -> bool:
	return InputMap.has_action(a)


# 将“链住的对象”解析成 MonsterBase。
# 兼容两种实现：
# - 直接射线命中怪物本体（CharacterBody2D with MonsterBase script）
# - 射线命中 EnemyHurtbox（Area2D），需要向上找父节点
func _resolve_monster(n: Node) -> MonsterBase:
	var cur: Node = n
	for _i in range(6):
		if cur == null:
			return null
		var mb := cur as MonsterBase
		if mb != null:
			return mb
		cur = cur.get_parent()
	return null


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

	# 确保缓冲一致
	_init_rope_buffers(c)
	_prealloc_line_points(c)
	_rebuild_weight_cache_if_needed(c)

	# 清理旧链接
	_detach_link_if_needed(idx)

	c.state = ChainState.FLYING
	c.end_pos = start
	c.end_vel = dir * chain_speed
	c.fly_t = 0.0
	c.hold_t = 0.0

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

	# 断裂预警（非溶解时）
	if c.state != ChainState.DISSOLVING:
		_apply_break_warning_color(c, start)

	match c.state:
		ChainState.FLYING:
			_update_chain_flying(i, dt)

		ChainState.STUCK:
			# STUCK：超过 hold_time 溶解
			c.hold_t += dt
			if c.hold_t >= hold_time:
				_begin_burn_dissolve(i)

		ChainState.LINKED:
			# LINKED：端点固定在目标挂点
			if c.linked_target == null or not is_instance_valid(c.linked_target):
				_begin_burn_dissolve(i)
				return

			c.end_pos = c.linked_target.global_position + c.linked_offset

			# 超过最大长度：断裂（溶解）
			if start.distance_to(c.end_pos) > chain_max_length:
				_begin_burn_dissolve(i)
				return

		ChainState.DISSOLVING:
			pass

	# ✅ 超长保护：FLYING/STUCK/LINKED 都要防
	if c.state != ChainState.DISSOLVING and start.distance_to(c.end_pos) > chain_max_length:
		_begin_burn_dissolve(i)
		return

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
		var col_obj: Object = hit["collider"]
		var col_node: Node = col_obj as Node

		# 命中瞬间余震
		c.wave_amp = maxf(c.wave_amp, rope_wave_amp * 0.6)

		# 1) 命中怪物：走 on_chain_hit（决定扣血并溶解 / 虚弱则链接）
		if col_node != null:
			var hit_target: Node = null
			if col_node.is_in_group("monster") and col_node.has_method("on_chain_hit"):
				hit_target = col_node
			else:
				var mb := _resolve_monster(col_node)
				if mb != null and mb.has_method("on_chain_hit"):
					hit_target = mb

			if hit_target != null:
				var ret: int = int(hit_target.call("on_chain_hit", self, i))
				if ret == 1:
					_attach_link(i, hit_target as Node2D, c.end_pos)
					return
				_begin_burn_dissolve(i)
				return

		# 2) 命中 Chimera：进入链接，并触发互动（ChimeraA.on_chain_attached）
		if col_node != null and col_node.has_method("on_chain_attached"):
			_attach_link(i, col_node as Node2D, c.end_pos)
			return

		# 3) 命中普通平台/静物：你要求“无视反弹+立刻消失特效”
		_begin_burn_dissolve(i)
		return

	# 超时未命中：停住
	if c.fly_t >= chain_max_fly_time:
		c.state = ChainState.STUCK
		c.hold_t = 0.0
		c.wave_amp = maxf(c.wave_amp, rope_wave_amp * 0.35)


func _attach_link(slot: int, target: Node2D, hit_pos: Vector2) -> void:
	if slot < 0 or slot >= chains.size():
		return
	var c := chains[slot]

	_detach_link_if_needed(slot)

	c.state = ChainState.LINKED
	c.linked_target = target
	if target != null:
		c.linked_offset = hit_pos - target.global_position
	else:
		c.linked_offset = Vector2.ZERO

	c.hold_t = 0.0

	# ✅ 通知目标进入“互动状态”
	if target != null and target.has_method("on_chain_attached"):
		target.call("on_chain_attached", slot)


func _detach_link_if_needed(slot: int) -> void:
	if slot < 0 or slot >= chains.size():
		return
	var c := chains[slot]
	if c.linked_target != null and is_instance_valid(c.linked_target):
		if c.linked_target.has_method("on_chain_detached"):
			c.linked_target.call("on_chain_detached", slot)
	c.linked_target = null
	c.linked_offset = Vector2.ZERO


func _begin_burn_dissolve(i: int, dissolve_time: float = -1.0, force: bool = false) -> void:
	if i < 0 or i >= chains.size():
		return
	var c := chains[i]
	if c.state == ChainState.IDLE:
		return
	if c.state == ChainState.DISSOLVING and not force:
		return

	# ✅ 断链时必须通知目标退出互动
	_detach_link_if_needed(i)

	# 材质（每次溶解要 reset burn=0）
	if c.burn_mat == null:
		if chain_shader_path == "" or chain_shader_path == null:
			chain_shader_path = DEFAULT_CHAIN_SHADER_PATH
		var sh := load(chain_shader_path) as Shader
		if sh == null:
			push_error("Cannot load chain shader: %s" % chain_shader_path)
			_finish_chain(i)
			return
		c.burn_mat = ShaderMaterial.new()
		c.burn_mat.shader = sh

	c.line.material = c.burn_mat
	c.burn_mat.set_shader_parameter("burn", 0.0)
	c.line.visible = true

	c.state = ChainState.DISSOLVING

	var t: float = burn_time if dissolve_time <= 0.0 else dissolve_time

	if c.burn_tw != null:
		c.burn_tw.kill()
		c.burn_tw = null

	c.burn_tw = create_tween()
	c.burn_tw.set_trans(Tween.TRANS_SINE)
	c.burn_tw.set_ease(Tween.EASE_IN_OUT)
	c.burn_tw.tween_property(c.burn_mat, "shader_parameter/burn", 1.0, t)
	c.burn_tw.tween_callback(func() -> void:
		_finish_chain(i)
	)


func _force_dissolve_all_chains() -> void:
	for i in range(chains.size()):
		var c := chains[i]
		if c.state == ChainState.IDLE or c.state == ChainState.DISSOLVING:
			continue
		# 停止当前抖动/效果
		c.wave_amp = 0.0
		c.wave_phase = 0.0
		_begin_burn_dissolve(i, cancel_dissolve_time, true)

func force_dissolve_chain(slot: int) -> void:
	if slot < 0 or slot >= chains.size():
		return
	var c := chains[slot]
	if c.state == ChainState.IDLE or c.state == ChainState.DISSOLVING:
		return
	c.wave_amp = 0.0
	c.wave_phase = 0.0
	_begin_burn_dissolve(slot, cancel_dissolve_time, true)


func _finish_chain(i: int) -> void:
	if i < 0 or i >= chains.size():
		return
	var c := chains[i]

	if c.burn_tw != null:
		c.burn_tw.kill()
		c.burn_tw = null

	c.state = ChainState.IDLE
	c.line.visible = false
	c.line.material = null
	c.line.modulate = Color.WHITE
	c.wave_amp = 0.0
	c.wave_phase = 0.0


# =========================
# 融合（两条链都 LINKED 且两只 monster 都弱）
# =========================
func _try_fuse() -> void:
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

	# 只允许融合 monster（Chimera 不参与融合）
	var m0: MonsterBase = _resolve_monster(c0.linked_target)
	var m1: MonsterBase = _resolve_monster(c1.linked_target)
	if m0 == null or m1 == null:
		return
	if not m0.weak or not m1.weak:
		return

	_player_locked = true
	velocity = Vector2.ZERO

	m0.set_fusion_vanish(true)
	m1.set_fusion_vanish(true)

	_begin_burn_dissolve(0, fusion_chain_dissolve_time)
	_begin_burn_dissolve(1, fusion_chain_dissolve_time)

	var tw := create_tween()
	tw.tween_interval(fusion_lock_time)
	tw.tween_callback(func() -> void:
		if is_instance_valid(m0): m0.queue_free()
		if is_instance_valid(m1): m1.queue_free()
		_spawn_chimera_at_player()
		_player_locked = false
	)


# =========================
# Chimera 安全生成：A（找不重叠点）+ B（禁碰撞1帧）
# =========================
func _spawn_chimera_at_player() -> void:
	if chimera_scene == null:
		return

	# 已有就不重复生成（你之后要多个再改）
	if _chimera != null and is_instance_valid(_chimera):
		if _chimera is Node2D:
			(_chimera as Node2D).global_position = global_position
		return

	var n := chimera_scene.instantiate()
	if not (n is Node2D):
		return

	var chim := n as Node2D
	get_parent().add_child(chim)

	# 先把它放到“临时位置”
	chim.global_position = global_position

	# 取它的碰撞形状（默认找子节点 CollisionShape2D）
	var body := chim as CollisionObject2D
	var cs: CollisionShape2D = chim.get_node_or_null(^"CollisionShape2D") as CollisionShape2D

	# 若没有碰撞体，直接生成（你的担心只发生在有碰撞时）
	if body == null or cs == null or cs.shape == null:
		_post_spawn_setup(chim)
		_chimera = chim
		return

	# B：先禁碰撞（避免刚加入就挤）
	var orig_layer: int = body.collision_layer
	var orig_mask: int = body.collision_mask
	var orig_disabled: bool = cs.disabled

	if spawn_disable_collision_one_frame:
		body.collision_layer = 0
		body.collision_mask = 0
		cs.disabled = true

	# A：找安全点
	var safe_pos: Vector2 = _find_safe_spawn_pos(cs.shape, chim.global_transform, global_position, orig_mask)
	chim.global_position = safe_pos

	# B：等待1帧后恢复碰撞
	if spawn_disable_collision_one_frame:
		await get_tree().process_frame
		if is_instance_valid(body) and is_instance_valid(cs):
			body.collision_layer = orig_layer
			body.collision_mask = orig_mask
			cs.disabled = orig_disabled

	_post_spawn_setup(chim)
	_chimera = chim


func _find_safe_spawn_pos(shape: Shape2D, chim_xform: Transform2D, base: Vector2, mask: int) -> Vector2:
	var space := get_world_2d().direct_space_state

	# 候选点：优先“上方”，其次“左右上方”，再更高
	var candidates: Array[Vector2] = []
	for k in range(1, spawn_try_up_count + 1):
		var up := Vector2(0.0, -spawn_try_up_step * float(k))
		candidates.append(base + up)
		candidates.append(base + up + Vector2(spawn_try_side, 0.0))
		candidates.append(base + up + Vector2(-spawn_try_side, 0.0))

	# 最后兜底：原地
	candidates.append(base)

	var q := PhysicsShapeQueryParameters2D.new()
	q.shape = shape
	q.collide_with_areas = false
	q.collide_with_bodies = true
	q.collision_mask = mask
	q.exclude = [self.get_rid()]  # 至少排除玩家

	for p in candidates:
		var xf := chim_xform
		xf.origin = p
		q.transform = xf
		var hits := space.intersect_shape(q, 8)
		if hits.size() == 0:
			return p

	return base


func _post_spawn_setup(chim: Node2D) -> void:
	# 兼容你 ChimeraA 的 API：setup(self) 或 set_player(self)
	if chim.has_method("setup"):
		chim.call("setup", self)
	elif chim.has_method("set_player"):
		chim.call("set_player", self)


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

	c.pts[0] = start_world
	c.pts[last] = end_world

	var start_delta: Vector2 = start_world - c.prev_start
	var end_delta: Vector2 = end_world - c.prev_end
	c.prev_start = start_world
	c.prev_end = end_world

	for k in range(1, last):
		var cur: Vector2 = c.pts[k]
		var vel: Vector2 = (cur - c.prev[k]) * rope_damping
		c.prev[k] = cur
		c.pts[k] = cur + vel + Vector2(0.0, rope_gravity)

	_rebuild_weight_cache_if_needed(c)
	for k in range(1, last):
		c.pts[k] += end_delta * (end_motion_inject * c.w_end[k])
		c.pts[k] += start_delta * (hand_motion_inject * c.w_start[k])

	if c.wave_amp > 0.001:
		c.wave_amp *= exp(-rope_wave_decay * dt)
		c.wave_phase += (rope_wave_freq * TAU) * dt

		var dir: Vector2 = end_world - start_world
		var perp: Vector2 = Vector2(-dir.y, dir.x)
		perp = (Vector2.UP if perp.length() < 0.001 else perp.normalized())

		for k in range(1, last):
			var t2: float = float(k) / float(last)
			var phase: float = c.wave_phase + (t2 * rope_wave_along_segments * TAU) + c.wave_seed * 10.0
			c.pts[k] += perp * (sin(phase) * c.wave_amp * c.w_end[k])

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
