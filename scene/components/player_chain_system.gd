extends Node
class_name PlayerChainSystem

## ============================================================================
## PlayerChainSystem - 终极整合版 (Zip1 物理 + Zip2 Spine + 完整修复)
## ============================================================================
## 
## 版本历史:
## - Zip1: 完美的Verlet绳索物理系统，但只支持Marker2D
## - Zip2: 添加Spine支持，但物理参数不完整
## - 本版本: 100%保留Zip1物理 + 支持Spine骨骼锚点 + Phase 1接口
##
## 核心特性:
## ✅ Zip1的26个美术参数（rope_segments, rope_wave_amp等）
## ✅ 完整的Verlet绳索模拟（_sim_rope方法）
## ✅ 自然波动叠加系统
## ✅ Spine骨骼锚点支持（chain_anchor_r/l）
## ✅ Marker2D fallback兼容
## ✅ Phase 1兼容接口（fire/cancel/release）
## ✅ 连续双发支持（pick_fire_side）
## ✅ 受击策略（cancel_volatile_on_damage）
##
## 美术调参入口:
## 所有参数都在 Player.gd 中定义为 @export 变量，美术可在Inspector直接调整
##
## ============================================================================

enum ChainState { IDLE, FLYING, STUCK, LINKED, DISSOLVING }

var player: Player
var hand_l: Node2D  # Marker2D（可选，Spine模式下可以为null）
var hand_r: Node2D  # Marker2D（可选，Spine模式下可以为null）

var _burn_shader: Shader = null
var _chimera: Node = null

##=== Phase 1 兼容接口：供 ActionFSM 使用 ===##

## slot_R_available: 右手链条槽位是否可用
var slot_R_available: bool:
	get:
		if chains.size() < 1:
			return true
		return chains[0].state == ChainState.IDLE

## slot_L_available: 左手链条槽位是否可用
var slot_L_available: bool:
	get:
		if chains.size() < 2:
			return true
		return chains[1].state == ChainState.IDLE

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
			var entity: EntityBase = system._resolve_entity(host_node)
			if entity != null and entity.has_method("on_chain_hit"):
				var ret_i: int = int(entity.call("on_chain_hit", system.player, slot))
				if ret_i == 1:
					system._attach_link(slot, entity as Node2D, c.end_pos)
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

	var pts: PackedVector2Array = PackedVector2Array()
	var prev: PackedVector2Array = PackedVector2Array()
	var prev_end: Vector2 = Vector2.ZERO
	var prev_start: Vector2 = Vector2.ZERO

	var wave_amp: float = 0.0
	var wave_phase: float = 0.0
	var wave_seed: float = 0.0

	var ray_q_block: PhysicsRayQueryParameters2D
	var ray_q_interact: PhysicsRayQueryParameters2D

	var burn_mat: ShaderMaterial
	var burn_tw: Tween

	var w_end: PackedFloat32Array = PackedFloat32Array()
	var w_start: PackedFloat32Array = PackedFloat32Array()
	var cached_n: int = -1
	var cached_hook_power: float = -999.0

	var linked_target: Node2D = null
	var linked_offset: Vector2 = Vector2.ZERO
	var interacted: Dictionary = {}
	
	var struggle_timer: float = 0.0
	var struggle_max: float = 5.0
	var is_chimera: bool = false


var chains: Array[ChainSlot] = []
var active_slot: int = 1

@export var debug_interact: bool = false

var _hit_resolver: ChainHitResolver
var _attach_policy: ChainAttachPolicy

func _ready() -> void:
	player = _find_player()
	if player == null:
		push_error("[ChainSystem] Player not found in parent chain.")
		set_process(false)
		return

	# === Zip2修复: Marker2D可选（Spine模式下可以为null） ===
	hand_l = player.get_node_or_null(player.hand_l_path) as Node2D
	hand_r = player.get_node_or_null(player.hand_r_path) as Node2D
	var line0: Line2D = player.get_node_or_null(player.chain_line0_path) as Line2D
	var line1: Line2D = player.get_node_or_null(player.chain_line1_path) as Line2D

	# 只检查Line2D（必须存在）
	if line0 == null or line1 == null:
		push_error("[ChainSystem] chain line paths invalid.")
		set_process(false)
		return
	
	# 警告：如果hand_l/hand_r都为null且没有animator，会fallback到player坐标
	if hand_l == null and hand_r == null:
		push_warning("[ChainSystem] HandL/HandR Marker2D not found, will use Spine bone anchors or player position.")

	if player.chain_shader_path == "" or player.chain_shader_path == null:
		player.chain_shader_path = player.DEFAULT_CHAIN_SHADER_PATH
	_burn_shader = load(player.chain_shader_path) as Shader

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


##=== Phase 1 兼容接口方法（供ActionFSM调用）===##

## setup(player): 兼容显式setup调用（可选）
func setup(p: CharacterBody2D) -> void:
	if p != null:
		player = p as Player


## fire(side): 发射链条（占用槽位）
## side: "R" 或 "L"
func fire(side: String) -> void:
	# Die硬闸 - 死亡时拒绝fire
	if player != null:
		var hp: int = player.health.hp if player.health != null else 1
		if hp <= 0:
			if player.has_method("log_msg"):
				player.log_msg("CHAIN", "fire(%s) REJECTED: hp=0" % side)
			return
		# 如果有action_fsm，也检查DIE状态
		if player.has_node("Components/ActionFSM"):
			var action_fsm = player.get_node("Components/ActionFSM")
			# === 修复：使用 state_name() 方法而不是反射 ===
			if action_fsm != null and action_fsm.has_method("state_name"):
				var current_state_name: StringName = action_fsm.state_name()
				if current_state_name == &"Die":
					if player.has_method("log_msg"):
						player.log_msg("CHAIN", "fire(%s) REJECTED: state=Die" % side)
					return
	
	var slot: int = 0 if side == "R" else 1
	if slot < 0 or slot >= chains.size():
		return
	
	_fire_chain_at_slot(slot)
	
	if player != null and player.has_method("log_msg"):
		player.log_msg("CHAIN", "fire(%s) sR=%s sL=%s" % [side, str(slot_R_available), str(slot_L_available)])


## cancel(side): 取消链条（立即释放槽位）
func cancel(side: String) -> void:
	var slot: int = 0 if side == "R" else 1
	force_dissolve_chain(slot)
	
	if player != null and player.has_method("log_msg"):
		player.log_msg("CHAIN", "cancel(%s) sR=%s sL=%s" % [side, str(slot_R_available), str(slot_L_available)])


## release(side): 链条动画正常结束后释放槽位
## 重要：LINKED状态不应被release破坏，只有FLYING/STUCK才finish
func release(side: String) -> void:
	var slot: int = 0 if side == "R" else 1
	if slot >= 0 and slot < chains.size():
		var c: ChainSlot = chains[slot]
		# 只在非绑定状态时才finish（FLYING/STUCK/DISSOLVING）
		# LINKED状态应该保持，直到玩家主动X取消或超时/机制解除
		if c.state != ChainState.IDLE and c.state != ChainState.LINKED:
			_finish_chain(slot)
	
	if player != null and player.has_method("log_msg"):
		player.log_msg("CHAIN", "release(%s) state=%s sR=%s sL=%s" % [
			side, 
			ChainState.keys()[chains[slot].state] if slot < chains.size() else "?",
			str(slot_R_available), 
			str(slot_L_available)
		])


## === Phase 2B: Slot 选择权接口 ===

## pick_fire_slot(): 返回应该发射的 slot index
func pick_fire_slot() -> int:
	if chains.size() < 2:
		return -1
	
	# 优先 active_slot
	if chains[active_slot].state == ChainState.IDLE:
		return active_slot
	
	# 其次尝试另一个 slot
	var other_slot: int = 1 - active_slot
	if chains[other_slot].state == ChainState.IDLE:
		return other_slot
	
	# 都忙
	return -1


## pick_fire_side(): 返回应该发射的手 "R" / "L" / ""
func pick_fire_side() -> String:
	var slot: int = pick_fire_slot()
	if slot == 0:
		return "R"
	elif slot == 1:
		return "L"
	else:
		return ""


## switch_slot(): 手动切换 active_slot（由 Tab 键触发）
func switch_slot() -> void:
	var new_slot: int = 1 - active_slot
	if active_slot != new_slot:
		active_slot = new_slot
		if EventBus != null and EventBus.has_method("slot_switched"):
			EventBus.slot_switched.emit(active_slot)
		
		if player != null and player.has_method("log_msg"):
			player.log_msg("CHAIN", "switch_slot → active_slot=%d" % active_slot)


## === Phase 2B: 受击策略 ===

## cancel_volatile_on_damage(): 受击时取消 FLYING/STUCK，但保留 LINKED
func cancel_volatile_on_damage() -> void:
	var cancelled_any: bool = false
	
	for i in range(chains.size()):
		var c: ChainSlot = chains[i]
		
		# 只取消 FLYING 和 STUCK，LINKED 保留
		if c.state == ChainState.FLYING or c.state == ChainState.STUCK:
			force_dissolve_chain(i)
			cancelled_any = true
	
	if cancelled_any and player != null and player.has_method("log_msg"):
		player.log_msg("CHAIN", "cancel_volatile_on_damage: cancelled FLYING/STUCK chains")


## _fire_chain_at_slot: 内部方法 - 发射指定槽位的链条到鼠标位置
func _fire_chain_at_slot(idx: int) -> void:
	if idx < 0 or idx >= chains.size():
		return
	
	var c: ChainSlot = chains[idx]
	if c.state != ChainState.IDLE:
		return  # 槽位已被占用
	
	# === Zip2核心修复: 使用_get_hand_position而不是直接访问Marker2D ===
	var start: Vector2 = _get_hand_position(c.use_right_hand)
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
	
	# 发射信号通知其他系统
	if EventBus != null and EventBus.has_method("emit_chain_fired"):
		EventBus.emit_chain_fired(idx)
	
	_switch_to_available_slot(idx)


##=== Zip2核心新增：锚点获取逻辑（Spine优先 → Marker2D fallback）===##

## _get_hand_position: 获取手部锚点位置
## 优先级：Animator骨骼桥接 → Marker2D → player坐标
func _get_hand_position(use_right_hand: bool) -> Vector2:
	# 1) 优先：通过Animator公开接口获取Spine骨骼位置
	if player.has_node("Animator"):
		var animator = player.get_node("Animator")
		if animator != null and animator.has_method("get_chain_anchor_position"):
			return animator.get_chain_anchor_position(use_right_hand)
	
	# 2) 兼容：旧anim_fsm（Phase 0遗留）
	if player.has_node("AnimFSM"):
		var anim_fsm = player.get_node("AnimFSM")
		if anim_fsm != null and anim_fsm.has_method("get_chain_anchor_position"):
			return anim_fsm.get_chain_anchor_position(use_right_hand)
	
	# 3) Fallback: Marker2D
	var hand: Node2D = hand_r if use_right_hand else hand_l
	if hand != null:
		return hand.global_position
	
	# 4) 最后兜底：player坐标
	return player.global_position


##=== Zip1原有方法（100%保留，只修改hand_r.global_position为_get_hand_position）===##


func tick(dt: float) -> void:
	for i: int in range(chains.size()):
		_update_chain(i, dt)


func handle_unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			var active_chain: ChainSlot = chains[active_slot]
			if active_chain.state == ChainState.LINKED and active_chain.is_chimera:
				var chimera: Node = active_chain.linked_target
				if chimera != null and chimera.has_method("on_player_interact"):
					chimera.call("on_player_interact", player)
				return
			_try_fire_chain()
			return

	if event is InputEventKey:
		var ek: InputEventKey = event as InputEventKey
		if not ek.pressed:
			return
		
		if ek.keycode == KEY_Z:
			_switch_slot()
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

	c.ray_q_block = PhysicsRayQueryParameters2D.new()
	c.ray_q_block.collide_with_areas = true
	c.ray_q_block.collide_with_bodies = true
	c.ray_q_block.hit_from_inside = true
	c.ray_q_block.collision_mask = player.chain_hit_mask
	c.ray_q_block.exclude = [player.get_rid()]

	c.ray_q_interact = PhysicsRayQueryParameters2D.new()
	c.ray_q_interact.collide_with_areas = true
	c.ray_q_interact.collide_with_bodies = false
	c.ray_q_interact.hit_from_inside = true
	c.ray_q_interact.collision_mask = player.chain_interact_mask
	c.ray_q_interact.exclude = [player.get_rid()]

	if _burn_shader != null:
		c.burn_mat = ShaderMaterial.new()
		c.burn_mat.shader = _burn_shader


func _init_line(l: Line2D) -> void:
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


func _resolve_entity(n: Node) -> EntityBase:
	var cur: Node = n
	for _i: int in range(6):
		if cur == null:
			return null
		var eb: EntityBase = cur as EntityBase
		if eb != null:
			return eb
		cur = cur.get_parent()
	return null


func _switch_slot() -> void:
	active_slot = 1 - active_slot
	if EventBus != null and EventBus.has_method("slot_switched"):
		EventBus.slot_switched.emit(active_slot)


func _switch_to_available_slot(from_slot: int) -> void:
	var other_slot: int = 1 - from_slot
	if chains[other_slot].state == ChainState.IDLE and active_slot != other_slot:
		active_slot = other_slot
		if EventBus != null and EventBus.has_method("slot_switched"):
			EventBus.slot_switched.emit(active_slot)


func _try_fire_chain() -> void:
	if chains.size() < 2:
		return

	var idx: int = -1
	if chains[active_slot].state == ChainState.IDLE:
		idx = active_slot
	elif chains[1 - active_slot].state == ChainState.IDLE:
		idx = 1 - active_slot
	else:
		return

	var c: ChainSlot = chains[idx]
	# === Zip2核心修复: 使用_get_hand_position ===
	var start: Vector2 = _get_hand_position(c.use_right_hand)
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
	
	if EventBus != null and EventBus.has_method("emit_chain_fired"):
		EventBus.emit_chain_fired(idx)
	
	_switch_to_available_slot(idx)


func _try_interact_from_inside(slot: int, start: Vector2) -> void:
	if slot < 0 or slot >= chains.size():
		return
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

	# === Zip2核心修复: 使用_get_hand_position ===
	var start: Vector2 = _get_hand_position(c.use_right_hand)

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
			
			if not c.is_chimera:
				c.struggle_timer += dt
				var progress: float = c.struggle_timer / c.struggle_max
				if EventBus != null and EventBus.has_method("chain_struggle_progress"):
					EventBus.chain_struggle_progress.emit(i, progress)
				if c.struggle_timer >= c.struggle_max:
					_on_struggle_break(i)
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


func _on_struggle_break(idx: int) -> void:
	if idx < 0 or idx >= chains.size():
		return
	_begin_burn_dissolve(idx)


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


func _handle_interact_area(slot: int, area: Area2D, source: String) -> void:
	if area == null:
		return
	var c: ChainSlot = chains[slot]
	var rid: RID = area.get_rid()
	if c.interacted.has(rid):
		return
	
	if debug_interact:
		var debug_host: Node = area.owner
		if debug_host == null:
			debug_host = area.get_parent()
		var host_name: String = String(debug_host.name) if debug_host != null else ""
		print("[ChainInteract:%s] slot=%d area=%s host=%s" % [source, slot, area.name, host_name])
	
	var host: Node = area.get_parent()
	if host == null:
		return
	
	if host.has_method("on_chain_hit"):
		var result: int = int(host.call("on_chain_hit", player, slot))
		if result != 0:
			c.interacted[rid] = true


func _attach_link(slot: int, target: Node2D, hit_pos: Vector2) -> void:
	if slot < 0 or slot >= chains.size():
		return
	var c: ChainSlot = chains[slot]
	var other_slot: int = 1 - slot
	
	if chains[other_slot].state == ChainState.LINKED:
		if chains[other_slot].linked_target == target:
			if target != null and target.has_method("take_damage"):
				target.call("take_damage", 1)
			_begin_burn_dissolve(slot, 0.3)
			return

	_detach_link_if_needed(slot)
	
	c.state = ChainState.LINKED
	c.linked_target = target
	c.linked_offset = (hit_pos - target.global_position) if target != null else Vector2.ZERO
	c.hold_t = 0.0
	c.struggle_timer = 0.0
	c.is_chimera = (target != null and target.is_in_group("chimera"))

	if target != null and target.has_method("on_chain_attached"):
		target.call("on_chain_attached", slot)
	
	var attr_type: int = -1
	var icon_id: int = -1
	if target != null:
		if target.has_method("get_attribute_type"):
			attr_type = target.call("get_attribute_type")
		if target.has_method("get_icon_id"):
			icon_id = target.call("get_icon_id")
	
	var should_show_anim: bool = c.is_chimera
	if not c.is_chimera:
		if target != null and target.has_method("get_weak_state"):
			should_show_anim = target.call("get_weak_state")
		if not should_show_anim and target != null and target.has_method("is_stunned"):
			should_show_anim = target.call("is_stunned")
	if EventBus != null and EventBus.has_method("emit_chain_bound"):
		EventBus.emit_chain_bound(slot, target, attr_type, icon_id, c.is_chimera, should_show_anim)
	_switch_to_available_slot(slot)


func _detach_link_if_needed(slot: int) -> void:
	if slot < 0 or slot >= chains.size():
		return
	var c: ChainSlot = chains[slot]
	if c.linked_target != null and is_instance_valid(c.linked_target):
		if c.linked_target.has_method("on_chain_detached"):
			c.linked_target.call("on_chain_detached", slot)
	c.linked_target = null
	c.linked_offset = Vector2.ZERO
	c.struggle_timer = 0.0
	c.is_chimera = false
	
	if c.state == ChainState.LINKED:
		if EventBus != null and EventBus.has_method("chain_released"):
			EventBus.chain_released.emit(slot, &"detached")


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
	
	if EventBus != null and EventBus.has_method("chain_released"):
		EventBus.chain_released.emit(i, &"dissolve")

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


## hard_clear_all_chains(reason): 立即清空所有链条（用于死亡/场景重置）
func hard_clear_all_chains(reason: String = "") -> void:
	var had_any: bool = false
	for i: int in range(chains.size()):
		if chains[i].state != ChainState.IDLE or chains[i].line.visible:
			had_any = true
			break
	for i: int in range(chains.size()):
		_hard_reset_slot(i)
	active_slot = 1
	if had_any and player != null and player.has_method("log_msg"):
		player.log_msg("CHAIN", "hard_clear_all reason=%s" % reason)

func _hard_reset_slot(i: int) -> void:
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
	_detach_link_if_needed(i)


func _finish_chain(i: int) -> void:
	if i < 0 or i >= chains.size():
		return
	var c: ChainSlot = chains[i]

	if c.burn_tw != null:
		c.burn_tw.kill()
		c.burn_tw = null
	
	# 如果还在LINKED状态，需要先detach并发信号
	if c.state == ChainState.LINKED:
		_detach_link_if_needed(i)

	c.state = ChainState.IDLE
	c.line.visible = false
	c.line.material = null
	c.line.modulate = Color.WHITE
	c.wave_amp = 0.0
	c.wave_phase = 0.0
	c.interacted.clear()
	
	var other_slot: int = 1 - i
	if chains[other_slot].state == ChainState.LINKED and not chains[other_slot].is_chimera:
		if active_slot != i:
			_switch_slot()


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
	if not is_instance_valid(c0.linked_target) or not is_instance_valid(c1.linked_target):
		return
	if c0.linked_target == c1.linked_target:
		return

	var entity_a: EntityBase = _resolve_entity(c0.linked_target)
	var entity_b: EntityBase = _resolve_entity(c1.linked_target)
	if entity_a == null or entity_b == null:
		return
	
	var a_can_fuse: bool = entity_a.weak or entity_a.is_stunned()
	var b_can_fuse: bool = entity_b.weak or entity_b.is_stunned()
	
	if not a_can_fuse or not b_can_fuse:
		if EventBus != null and EventBus.has_method("fusion_rejected"):
			EventBus.fusion_rejected.emit()
		return
	
	var result: Dictionary = FusionRegistry.check_fusion(entity_a, entity_b)
	
	if result.type == FusionRegistry.FusionResultType.REJECTED:
		if EventBus != null and EventBus.has_method("fusion_rejected"):
			EventBus.fusion_rejected.emit()
		return
	
	player.set_player_locked(true)
	player.velocity = Vector2.ZERO

	if entity_a.has_method("set_fusion_vanish"):
		entity_a.call("set_fusion_vanish", true)
	if entity_b.has_method("set_fusion_vanish"):
		entity_b.call("set_fusion_vanish", true)

	_begin_burn_dissolve(0, player.fusion_chain_dissolve_time)
	_begin_burn_dissolve(1, player.fusion_chain_dissolve_time)

	var tw: Tween = create_tween()
	tw.tween_interval(player.fusion_lock_time)
	tw.tween_callback(func() -> void:
		var spawned: Node = FusionRegistry.execute_fusion(result, player)
		if spawned != null:
			_chimera = spawned
		player.set_player_locked(false)
	)


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


func _reset_rope_line(c: ChainSlot, start_world: Vector2, end_world: Vector2) -> void:
	var n: int = c.pts.size()
	if n < 2:
		return
	for k: int in range(n):
		var t: float = float(k) / float(n - 1)
		var p: Vector2 = start_world.lerp(end_world, t)
		c.pts[k] = p
		c.prev[k] = p


## === Zip1核心：完整的Verlet绳索物理模拟（100%保留）===
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

	# Verlet积分
	for k: int in range(1, last):
		var cur: Vector2 = c.pts[k]
		var vel: Vector2 = (cur - c.prev[k]) * player.rope_damping
		c.prev[k] = cur
		c.pts[k] = cur + vel + Vector2(0.0, player.rope_gravity)

	# 运动注入（手和钩子运动传导）
	_rebuild_weight_cache_if_needed(c)
	for k: int in range(1, last):
		c.pts[k] += end_delta * (player.end_motion_inject * c.w_end[k])
		c.pts[k] += start_delta * (player.hand_motion_inject * c.w_start[k])

	# 自然波动叠加
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

	# 刚度约束（Verlet迭代）
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
