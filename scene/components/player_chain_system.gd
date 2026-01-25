extends Node
class_name PlayerChainSystem

enum ChainState { IDLE, FLYING, STUCK, LINKED, DISSOLVING }

var player: Player
var hand_l: Node2D
var hand_r: Node2D

var _burn_shader: Shader = null
var _chimera: Node = null

class ChainHitResolver:
	var system: PlayerChainSystem

	func _init(owner: PlayerChainSystem) -> void:
		system = owner

	func resolve_chain_hits(c: ChainSlot, prev_pos: Vector2, end_pos: Vector2) -> Dictionary:
		var space: PhysicsDirectSpaceState2D = system.player.get_world_2d().direct_space_state

		c.ray_q_block.from = prev_pos
		c.ray_q_block.to = end_pos
		c.ray_q_interact.from = prev_pos
		c.ray_q_interact.to = end_pos

		var hit_interact: Dictionary = space.intersect_ray(c.ray_q_interact)

		var hit_block: Dictionary = {}
		var block_pos: Vector2 = Vector2.ZERO
		var ex: Array[RID] = [system.player.get_rid()]
		for _k: int in range(6):
			c.ray_q_block.exclude = ex
			var hb: Dictionary = space.intersect_ray(c.ray_q_block)
			if hb.size() == 0:
				break

			var col_obj_b: Object = hb.get("collider")
			var col_b: CollisionObject2D = col_obj_b as CollisionObject2D
			if col_b != null:
				if (col_b.collision_layer & system.player.chain_interact_mask) != 0:
					ex.append(col_b.get_rid())
					continue

			hit_block = hb
			block_pos = hb["position"]
			break

		var allow_interact: bool = true
		if hit_interact.size() > 0 and hit_block.size() > 0:
			var interact_pos: Vector2 = hit_interact["position"]
			var db: float = prev_pos.distance_to(block_pos)
			var di: float = prev_pos.distance_to(interact_pos)
			allow_interact = (di <= db + 0.001)

		return {
			"hit_interact": hit_interact,
			"hit_block": hit_block,
			"allow_interact": allow_interact,
		}

class ChainAttachPolicy:
	var system: PlayerChainSystem

	func _init(owner: PlayerChainSystem) -> void:
		system = owner

	func handle_interact_hit(slot: int, hit_interact: Dictionary) -> void:
		var col_obj: Object = hit_interact.get("collider")
		var area: Area2D = col_obj as Area2D
		system._handle_interact_area(slot, area, "ray")

	func handle_block_hit(slot: int, hit_block: Dictionary) -> void:
		var c: ChainSlot = system.chains[slot]

		c.end_pos = hit_block["position"]

		var col_obj: Object = hit_block.get("collider")
		var col_node: Node = col_obj as Node

		var host_node: Node = col_node

		if col_node != null and col_node.is_in_group("enemy_hurtbox") and col_node.has_method("get_host"):
			var h: Node = col_node.call("get_host") as Node
			if h != null:
				host_node = h

		if col_node is Area2D and (not col_node.is_in_group("enemy_hurtbox")):
			var p: Node = (col_node as Area2D).get_parent()
			if p != null:
				host_node = p

		c.wave_amp = maxf(c.wave_amp, system.player.rope_wave_amp * 0.6)

		if host_node != null:
			var mb: MonsterBase = system._resolve_monster(host_node)
			if mb != null and mb.has_method("on_chain_hit"):
				var ret_i: int = int(mb.call("on_chain_hit", system.player, slot))
				if ret_i == 1:
					system._attach_link(slot, mb as Node2D, c.end_pos)
					return
				system._begin_burn_dissolve(slot)
				return

		if host_node != null and host_node.has_method("on_chain_attached"):
			system._attach_link(slot, host_node as Node2D, c.end_pos)
			return

		system._begin_burn_dissolve(slot)

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

	# RayQuery（阻挡 / 交互分离）
	var ray_q_block: PhysicsRayQueryParameters2D
	var ray_q_interact: PhysicsRayQueryParameters2D

	# 每条链预创建溶解材质（避免串台）
	var burn_mat: ShaderMaterial
	var burn_tw: Tween

	# 权重缓存
	var w_end: PackedFloat32Array = PackedFloat32Array()
	var w_start: PackedFloat32Array = PackedFloat32Array()
	var cached_n: int = -1
	var cached_hook_power: float = -999.0

	# 链接对象（monster/chimera 都走这套）
	var linked_target: Node2D = null
	var linked_offset: Vector2 = Vector2.ZERO

	# 交互去重（避免一帧/多帧重复触发同一个花）
	var interacted: Dictionary = {} # key: RID -> true


var chains: Array[ChainSlot] = []

@export var debug_interact: bool = false

var _hit_resolver: ChainHitResolver
var _attach_policy: ChainAttachPolicy

func _ready() -> void:
	player = _find_player()
	if player == null:
		push_error("[ChainSystem] Player not found in parent chain.")
		set_process(false)
		return

	hand_l = player.get_node_or_null(player.hand_l_path) as Node2D
	hand_r = player.get_node_or_null(player.hand_r_path) as Node2D
	var line0: Line2D = player.get_node_or_null(player.chain_line0_path) as Line2D
	var line1: Line2D = player.get_node_or_null(player.chain_line1_path) as Line2D

	if hand_l == null or hand_r == null or line0 == null or line1 == null:
		push_error("[ChainSystem] hand/line node paths invalid. Check Player inspector paths.")
		set_process(false)
		return

	# shader（完全复刻原版）
	if player.chain_shader_path == "" or player.chain_shader_path == null:
		player.chain_shader_path = player.DEFAULT_CHAIN_SHADER_PATH
	_burn_shader = load(player.chain_shader_path) as Shader
	if _burn_shader == null:
		push_error("[ChainSystem] cannot load chain shader: %s" % player.chain_shader_path)

	chains.clear()
	chains.resize(2)

	var c0: ChainSlot = ChainSlot.new()
	c0.use_right_hand = true
	c0.line = line0
	c0.wave_seed = 0.37
	_setup_chain_slot(c0)
	chains[0] = c0

	var c1: ChainSlot = ChainSlot.new()
	c1.use_right_hand = false
	c1.line = line1
	c1.wave_seed = 0.81
	_setup_chain_slot(c1)
	chains[1] = c1

	_hit_resolver = ChainHitResolver.new(self)
	_attach_policy = ChainAttachPolicy.new(self)


func tick(dt: float) -> void:
	for i: int in range(chains.size()):
		_update_chain(i, dt)


# ✅ 你 Player.gd 现在就是在 call 这个名字：必须存在
func handle_unhandled_input(event: InputEvent) -> void:
	# 鼠标左键：发射锁链
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_try_fire_chain()
			return

	# 空格：融合；X：强制消失
	if event is InputEventKey:
		var ek: InputEventKey = event as InputEventKey
		if not ek.pressed:
			return

		var fuse_pressed: bool = false
		if _has_action(player.action_fuse):
			fuse_pressed = Input.is_action_just_pressed(player.action_fuse)
		else:
			fuse_pressed = (ek.keycode == KEY_SPACE)
		if fuse_pressed:
			_try_fuse()
			return

		var cancel_pressed: bool = false
		if _has_action(player.action_cancel_chains):
			cancel_pressed = Input.is_action_just_pressed(player.action_cancel_chains)
		else:
			cancel_pressed = (ek.keycode == KEY_X)
		if cancel_pressed:
			_force_dissolve_all_chains()
			return


func _find_player() -> Player:
	var p: Node = self
	while p != null and not (p is Player):
		p = p.get_parent()
	return p as Player


func _has_action(a: StringName) -> bool:
	return InputMap.has_action(a)


func _setup_chain_slot(c: ChainSlot) -> void:
	_init_line(c.line)
	_init_rope_buffers(c)
	_prealloc_line_points(c)
	_rebuild_weight_cache_if_needed(c)

	# 阻挡 ray：只负责“会挡住链/会挂链”的东西
	c.ray_q_block = PhysicsRayQueryParameters2D.new()
	c.ray_q_block.collide_with_areas = true
	c.ray_q_block.collide_with_bodies = true
	c.ray_q_block.hit_from_inside = true
	c.ray_q_block.collision_mask = player.chain_hit_mask
	c.ray_q_block.exclude = [player.get_rid()]

	# 交互 ray：只负责“触发花等交互”，永不阻挡
	c.ray_q_interact = PhysicsRayQueryParameters2D.new()
	c.ray_q_interact.collide_with_areas = true
	c.ray_q_interact.collide_with_bodies = false
	c.ray_q_interact.hit_from_inside = true
	c.ray_q_interact.collision_mask = player.chain_interact_mask
	c.ray_q_interact.exclude = [player.get_rid()]

	if _burn_shader != null:
		c.burn_mat = ShaderMaterial.new()
		c.burn_mat.shader = _burn_shader
	else:
		c.burn_mat = null


func _init_line(l: Line2D) -> void:
	# ✅ 复刻原版：不碰 width/texture/gradient（它们是 Inspector 的“默认值”）
	l.visible = false
	l.material = null
	l.modulate = Color.WHITE


func _init_rope_buffers(c: ChainSlot) -> void:
	var n: int = max(player.rope_segments + 1, 2)
	c.pts.resize(n)
	c.prev.resize(n)
	for i: int in range(n):
		c.pts[i] = player.global_position
		c.prev[i] = player.global_position
	c.prev_end = player.global_position
	c.prev_start = player.global_position


func _prealloc_line_points(c: ChainSlot) -> void:
	var n: int = c.pts.size()
	if c.line.get_point_count() != n:
		c.line.clear_points()
		for _i: int in range(n):
			c.line.add_point(Vector2.ZERO)


func _rebuild_weight_cache_if_needed(c: ChainSlot) -> void:
	var n: int = c.pts.size()
	if c.cached_n == n and is_equal_approx(c.cached_hook_power, player.rope_wave_hook_power):
		return

	c.cached_n = n
	c.cached_hook_power = player.rope_wave_hook_power

	c.w_end.resize(n)
	c.w_start.resize(n)
	if n <= 1:
		return

	var inv: float = 1.0 / float(n - 1)
	for k: int in range(n):
		var t: float = float(k) * inv
		c.w_end[k] = pow(t, player.rope_wave_hook_power)
		c.w_start[k] = pow(1.0 - t, 1.6)


func _resolve_monster(n: Node) -> MonsterBase:
	var cur: Node = n
	for _i: int in range(6):
		if cur == null:
			return null
		var mb: MonsterBase = cur as MonsterBase
		if mb != null:
			return mb
		cur = cur.get_parent()
	return null


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

	var c: ChainSlot = chains[idx]
	var start: Vector2 = (hand_r.global_position if c.use_right_hand else hand_l.global_position)
	var target: Vector2 = player.get_global_mouse_position()

	var dir: Vector2 = target - start
	if dir.length() < 0.001:
		dir = Vector2(float(player.facing), 0.0)
	else:
		dir = dir.normalized()

	_init_rope_buffers(c)
	_prealloc_line_points(c)
	_rebuild_weight_cache_if_needed(c)

	_detach_link_if_needed(idx)

	c.interacted.clear()
	_try_interact_from_inside(idx, start)

	c.state = ChainState.FLYING
	c.end_pos = start
	c.end_vel = dir * player.chain_speed
	c.fly_t = 0.0
	c.hold_t = 0.0

	c.wave_amp = player.rope_wave_amp
	c.wave_phase = 0.0

	c.line.visible = true
	c.line.material = null
	c.line.modulate = Color.WHITE

	_reset_rope_line(c, start, c.end_pos)
	c.prev_start = start
	c.prev_end = c.end_pos


func _try_interact_from_inside(slot: int, start: Vector2) -> void:
	if slot < 0 or slot >= chains.size():
		return
	var c: ChainSlot = chains[slot]
	var space: PhysicsDirectSpaceState2D = player.get_world_2d().direct_space_state
	var circle := CircleShape2D.new()
	circle.radius = 6.0

	var qp := PhysicsShapeQueryParameters2D.new()
	qp.shape = circle
	qp.transform = Transform2D(0.0, start)
	qp.collide_with_areas = true
	qp.collide_with_bodies = false
	qp.collision_mask = player.chain_interact_mask
	qp.exclude = [player.get_rid()]

	var hits := space.intersect_shape(qp, 16)
	for hit in hits:
		var area := hit.get("collider") as Area2D
		_handle_interact_area(slot, area, "inside")


func _update_chain(i: int, dt: float) -> void:
	if i < 0 or i >= chains.size():
		return

	var c: ChainSlot = chains[i]
	if c.state == ChainState.IDLE:
		return

	var start: Vector2 = (hand_r.global_position if c.use_right_hand else hand_l.global_position)

	if c.state != ChainState.DISSOLVING:
		_apply_break_warning_color(c, start)

	match c.state:
		ChainState.FLYING:
			_update_chain_flying(i, dt)
		ChainState.STUCK:
			c.hold_t += dt
			if c.hold_t >= player.hold_time:
				_begin_burn_dissolve(i)
		ChainState.LINKED:
			if c.linked_target == null or not is_instance_valid(c.linked_target):
				_begin_burn_dissolve(i)
				return
			c.end_pos = c.linked_target.global_position + c.linked_offset
			if start.distance_to(c.end_pos) > player.chain_max_length:
				_begin_burn_dissolve(i)
				return
		ChainState.DISSOLVING:
			pass

	if c.state != ChainState.DISSOLVING and start.distance_to(c.end_pos) > player.chain_max_length:
		_begin_burn_dissolve(i)
		return

	_sim_rope(c, start, c.end_pos, dt)
	_apply_rope_to_line_fast(c)


func _apply_break_warning_color(c: ChainSlot, start: Vector2) -> void:
	var d: float = start.distance_to(c.end_pos)
	var r: float = clamp(d / player.chain_max_length, 0.0, 1.0)

	if r <= player.warn_start_ratio:
		c.line.modulate = Color.WHITE
		return

	var t: float = (r - player.warn_start_ratio) / maxf(1.0 - player.warn_start_ratio, 0.0001)
	t = pow(t, player.warn_gamma)
	c.line.modulate = Color.WHITE.lerp(player.warn_color, t)


# ============================
# ✅ 核心修正：阻挡/交互分离 + 强制“花永不阻挡”
# ============================
func _update_chain_flying(i: int, dt: float) -> void:
	var c: ChainSlot = chains[i]

	var prev_pos: Vector2 = c.end_pos
	c.end_pos = c.end_pos + c.end_vel * dt
	c.fly_t += dt

	var hit_result: Dictionary = _hit_resolver.resolve_chain_hits(c, prev_pos, c.end_pos)
	var hit_interact: Dictionary = hit_result["hit_interact"]
	var hit_block: Dictionary = hit_result["hit_block"]
	var allow_interact: bool = hit_result["allow_interact"]

	if hit_interact.size() > 0 and allow_interact:
		_attach_policy.handle_interact_hit(i, hit_interact)

	if hit_block.size() > 0:
		_attach_policy.handle_block_hit(i, hit_block)
		return

	if c.fly_t >= player.chain_max_fly_time:
		c.state = ChainState.STUCK
		c.hold_t = 0.0
		c.wave_amp = maxf(c.wave_amp, player.rope_wave_amp * 0.35)


func _process_interact_hit(slot: int, hit_interact: Dictionary) -> void:
	_attach_policy.handle_interact_hit(slot, hit_interact)


func _handle_interact_area(slot: int, area: Area2D, source: String) -> void:
	if area == null:
		return
	var c: ChainSlot = chains[slot]
	var rid: RID = area.get_rid()
	if c.interacted.has(rid):
		return

	if debug_interact:
		var host: Node = area.owner
		if host == null:
			host = area.get_parent()
		var host_name: String = host.name if host != null else "null"
		print("[ChainInteract:%s] slot=%d area=%s host=%s" % [source, slot, area.name, host_name])
	c.interacted[rid] = true

	var host: Node = area.get_parent()
	if host == null:
		return

	# 约束：交互对象要自己实现 on_chain_hit(player, slot)
	if host.has_method("on_chain_hit"):
		host.call("on_chain_hit", player, slot)


func _process_block_hit(slot: int, hit_block: Dictionary) -> void:
	_attach_policy.handle_block_hit(slot, hit_block)


func _attach_link(slot: int, target: Node2D, hit_pos: Vector2) -> void:
	if slot < 0 or slot >= chains.size():
		return
	var c: ChainSlot = chains[slot]

	_detach_link_if_needed(slot)

	c.state = ChainState.LINKED
	c.linked_target = target
	c.linked_offset = (hit_pos - target.global_position) if target != null else Vector2.ZERO
	c.hold_t = 0.0

	if target != null and target.has_method("on_chain_attached"):
		target.call("on_chain_attached", slot)


func _detach_link_if_needed(slot: int) -> void:
	if slot < 0 or slot >= chains.size():
		return
	var c: ChainSlot = chains[slot]
	if c.linked_target != null and is_instance_valid(c.linked_target):
		if c.linked_target.has_method("on_chain_detached"):
			c.linked_target.call("on_chain_detached", slot)
	c.linked_target = null
	c.linked_offset = Vector2.ZERO


func _begin_burn_dissolve(i: int, dissolve_time: float = -1.0, force: bool = false) -> void:
	if i < 0 or i >= chains.size():
		return
	var c: ChainSlot = chains[i]
	if c.state == ChainState.IDLE:
		return
	if c.state == ChainState.DISSOLVING and not force:
		return

	_detach_link_if_needed(i)

	if c.burn_mat == null:
		if player.chain_shader_path == "" or player.chain_shader_path == null:
			player.chain_shader_path = player.DEFAULT_CHAIN_SHADER_PATH
		var sh: Shader = load(player.chain_shader_path) as Shader
		if sh == null:
			push_error("Cannot load chain shader: %s" % player.chain_shader_path)
			_finish_chain(i)
			return
		c.burn_mat = ShaderMaterial.new()
		c.burn_mat.shader = sh

	c.line.material = c.burn_mat
	c.burn_mat.set_shader_parameter("burn", 0.0)
	c.line.visible = true

	c.state = ChainState.DISSOLVING

	var t: float = player.burn_time if dissolve_time <= 0.0 else dissolve_time

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
	for i: int in range(chains.size()):
		var c: ChainSlot = chains[i]
		if c.state == ChainState.IDLE or c.state == ChainState.DISSOLVING:
			continue
		c.wave_amp = 0.0
		c.wave_phase = 0.0
		_begin_burn_dissolve(i, player.cancel_dissolve_time, true)


func force_dissolve_chain(slot: int) -> void:
	if slot < 0 or slot >= chains.size():
		return
	var c: ChainSlot = chains[slot]
	if c.state == ChainState.IDLE or c.state == ChainState.DISSOLVING:
		return
	c.wave_amp = 0.0
	c.wave_phase = 0.0
	_begin_burn_dissolve(slot, player.cancel_dissolve_time, true)


func force_dissolve_all_chains() -> void:
	_force_dissolve_all_chains()


func _finish_chain(i: int) -> void:
	if i < 0 or i >= chains.size():
		return
	var c: ChainSlot = chains[i]

	if c.burn_tw != null:
		c.burn_tw.kill()
		c.burn_tw = null

	c.state = ChainState.IDLE
	c.line.visible = false
	c.line.material = null
	c.line.modulate = Color.WHITE
	c.wave_amp = 0.0
	c.wave_phase = 0.0
	c.interacted.clear()


func _try_fuse() -> void:
	if player.is_player_locked():
		return
	if chains.size() < 2:
		return

	var c0: ChainSlot = chains[0]
	var c1: ChainSlot = chains[1]

	if c0.state != ChainState.LINKED or c1.state != ChainState.LINKED:
		return
	if c0.linked_target == null or c1.linked_target == null:
		return
	if c0.linked_target == c1.linked_target:
		return

	var m0: MonsterBase = _resolve_monster(c0.linked_target)
	var m1: MonsterBase = _resolve_monster(c1.linked_target)
	if m0 == null or m1 == null:
		return
	if not m0.weak or not m1.weak:
		return

	player.set_player_locked(true)
	player.velocity = Vector2.ZERO

	m0.set_fusion_vanish(true)
	m1.set_fusion_vanish(true)

	_begin_burn_dissolve(0, player.fusion_chain_dissolve_time)
	_begin_burn_dissolve(1, player.fusion_chain_dissolve_time)

	var tw: Tween = create_tween()
	tw.tween_interval(player.fusion_lock_time)
	tw.tween_callback(func() -> void:
		if is_instance_valid(m0): m0.queue_free()
		if is_instance_valid(m1): m1.queue_free()
		_spawn_chimera_at_player()
		player.set_player_locked(false)
	)


func _spawn_chimera_at_player() -> void:
	if player.chimera_scene == null:
		return

	if _chimera != null and is_instance_valid(_chimera):
		if _chimera is Node2D:
			(_chimera as Node2D).global_position = player.global_position
		return

	var n: Node = (player.chimera_scene as PackedScene).instantiate()
	if not (n is Node2D):
		return

	var chim: Node2D = n as Node2D
	player.get_parent().add_child(chim)
	chim.global_position = player.global_position

	var body: CollisionObject2D = chim as CollisionObject2D
	var cs: CollisionShape2D = chim.get_node_or_null(^"CollisionShape2D") as CollisionShape2D
	if body == null or cs == null or cs.shape == null:
		_post_spawn_setup(chim)
		_chimera = chim
		return

	var orig_layer: int = body.collision_layer
	var orig_mask: int = body.collision_mask
	var orig_disabled: bool = cs.disabled

	if player.spawn_disable_collision_one_frame:
		body.collision_layer = 0
		body.collision_mask = 0
		cs.disabled = true

	var safe_pos: Vector2 = _find_safe_spawn_pos(cs.shape, chim.global_transform, player.global_position, orig_mask)
	chim.global_position = safe_pos

	if player.spawn_disable_collision_one_frame:
		await get_tree().process_frame
		if is_instance_valid(body) and is_instance_valid(cs):
			body.collision_layer = orig_layer
			body.collision_mask = orig_mask
			cs.disabled = orig_disabled

	_post_spawn_setup(chim)
	_chimera = chim


func _find_safe_spawn_pos(shape: Shape2D, chim_xform: Transform2D, base: Vector2, mask: int) -> Vector2:
	var space: PhysicsDirectSpaceState2D = player.get_world_2d().direct_space_state

	var candidates: Array[Vector2] = []
	for k: int in range(1, player.spawn_try_up_count + 1):
		var up: Vector2 = Vector2(0.0, -player.spawn_try_up_step * float(k))
		candidates.append(base + up)
		candidates.append(base + up + Vector2(player.spawn_try_side, 0.0))
		candidates.append(base + up + Vector2(-player.spawn_try_side, 0.0))
	candidates.append(base)

	var q: PhysicsShapeQueryParameters2D = PhysicsShapeQueryParameters2D.new()
	q.shape = shape
	q.collide_with_areas = false
	q.collide_with_bodies = true
	q.collision_mask = mask
	q.exclude = [player.get_rid()]

	for p: Vector2 in candidates:
		var xf: Transform2D = chim_xform
		xf.origin = p
		q.transform = xf
		var hits: Array = space.intersect_shape(q, 8)
		if hits.size() == 0:
			return p
	return base


func _post_spawn_setup(chim: Node2D) -> void:
	if chim.has_method("setup"):
		chim.call("setup", player)
	elif chim.has_method("set_player"):
		chim.call("set_player", player)


func _reset_rope_line(c: ChainSlot, start_world: Vector2, end_world: Vector2) -> void:
	var n: int = c.pts.size()
	if n < 2:
		return
	for k: int in range(n):
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

	for k: int in range(1, last):
		var cur: Vector2 = c.pts[k]
		var vel: Vector2 = (cur - c.prev[k]) * player.rope_damping
		c.prev[k] = cur
		c.pts[k] = cur + vel + Vector2(0.0, player.rope_gravity)

	_rebuild_weight_cache_if_needed(c)
	for k: int in range(1, last):
		c.pts[k] += end_delta * (player.end_motion_inject * c.w_end[k])
		c.pts[k] += start_delta * (player.hand_motion_inject * c.w_start[k])

	if c.wave_amp > 0.001:
		c.wave_amp *= exp(-player.rope_wave_decay * dt)
		c.wave_phase += (player.rope_wave_freq * TAU) * dt

		var dir: Vector2 = end_world - start_world
		var perp: Vector2 = Vector2(-dir.y, dir.x)
		perp = (Vector2.UP if perp.length() < 0.001 else perp.normalized())

		for k: int in range(1, last):
			var t2: float = float(k) / float(last)
			var phase: float = c.wave_phase + (t2 * player.rope_wave_along_segments * TAU) + c.wave_seed * 10.0
			c.pts[k] += perp * (sin(phase) * c.wave_amp * c.w_end[k])

	var total_len: float = start_world.distance_to(end_world)
	var seg_len: float = total_len / float(last)

	for _it: int in range(player.rope_iterations):
		c.pts[0] = start_world
		c.pts[last] = end_world

		for k: int in range(last):
			var a: Vector2 = c.pts[k]
			var b: Vector2 = c.pts[k + 1]
			var delta: Vector2 = b - a
			var d: float = maxf(delta.length(), 0.0001)
			var diff: float = (d - seg_len) / d
			var adj: Vector2 = delta * (0.5 * player.rope_stiffness * diff)

			if k != 0:
				c.pts[k] += adj
			if k + 1 != last:
				c.pts[k + 1] -= adj


func _apply_rope_to_line_fast(c: ChainSlot) -> void:
	var n: int = c.pts.size()
	if c.line.get_point_count() != n:
		_prealloc_line_points(c)

	if player.texture_anchor_at_hook:
		for i: int in range(n):
			var src: int = (n - 1) - i
			c.line.set_point_position(i, c.line.to_local(c.pts[src]))
	else:
		for i: int in range(n):
			c.line.set_point_position(i, c.line.to_local(c.pts[i]))
