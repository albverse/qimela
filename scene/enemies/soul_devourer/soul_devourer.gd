extends MonsterBase
class_name SoulDevourer

## =============================================================================
## SoulDevourer — 噬魂犬（Soul Devourer）
## =============================================================================
## 蓝图：docs/progress/SOUL_DEVOURER_BLUEPRINT.md v0.5.4
## 属性：DARK，体型：MEDIUM，HP：3，weak_hp：1
##
## 核心规则：
## - 唯一有效伤害：ghost_fist 命中 FireHurtbox（项目命中管线路由）
## - 全状态不可 chain：on_chain_hit() 恒返回 0
## - 无 stun：apply_stun() 空操作
## - weak → death-rebirth（不走基类 weak 链路）
## - 双文件夹动画系统：normal/ 和 has_knife/
## - 行为由 Beehave 行为树驱动
## =============================================================================

# ===== 数值 =====
@export var ground_run_speed: float = 90.0
@export var float_move_speed: float = 70.0
@export var hunt_timeout: float = 4.0
@export var move_to_cleaver_timeout: float = 5.0
@export var knife_attack_timeout: float = 2.2
@export var forced_invisible_duration: float = 5.0
@export var rebirth_delay: float = 10.0
@export var attack_cooldown_has_knife: float = 1.0
@export var skill_cooldown_has_knife: float = 5.0
@export var skill_cooldown_light_beam: float = 5.0
@export var knife_attack_overshoot: float = 200.0
@export var knife_attack_trigger_dist: float = 40.0
@export var light_beam_min_distance: float = 150.0
@export var forced_invisible_trigger_dist: float = 100.0
@export var forced_invisible_maintain_dist: float = 150.0
@export var separate_distance: float = 200.0
@export var merge_move_speed: float = 150.0
@export var separate_speed: float = 120.0
@export var fall_speed: float = 300.0
@export var dual_beam_damage: int = 1

# ===== 行为标志 =====
var _aggro_mode: bool = false
var _is_full: bool = false
var _hunt_succeed_playing: bool = false  # huntting_succeed 动画播放中，条件保持 SUCCESS
var _has_knife: bool = false
var _pickup_anim_playing: bool = false
var _is_floating_invisible: bool = false
var _forced_invisible: bool = false

# ===== Death-Rebirth 标志 =====
var _death_rebirth_started: bool = false   # 防重入 guard
var _is_dead_hidden: bool = false          # death 播完后的隐藏等待期
var _is_respawning: bool = false           # born 动画播放中

# ===== 锁定标志 =====
var _landing_locked: bool = false
var _pending_death_rebirth: bool = false   # 着陆期间命中排队
var _merging: bool = false
var _force_separate: bool = false

# ===== 目标 =====
var _current_target_ghost: Node = null
var _current_target_cleaver: Node = null

# ===== 辅助 =====
var _spawn_point: Vector2
var _knife_attack_count: int = 0

# ===== 近期伤害追踪（用于强制隐身条件）=====
var _recent_damage_amount: float = 0.0
var _recent_damage_timer: float = 0.0
const RECENT_DAMAGE_WINDOW: float = 1.0

# ===== Hurt 受击僵直 =====
var _hurt_active: bool = false
var _hurt_timer: float = 0.0
const HURT_STUN_DURATION: float = 0.2

# ===== 面向死区 =====
const FACE_DEAD_ZONE: float = 30.0

# ===== 动画系统 =====
var _current_anim: StringName = &""
var _current_anim_finished: bool = false
var _current_anim_loop: bool = false
var _anim_driver: AnimDriverSpine = null
var _anim_mock: AnimDriverMock = null

# ===== 节点引用 =====
@onready var _spine_sprite: Node = get_node_or_null("SpineSprite")
@onready var _fire_hurtbox: Area2D = get_node_or_null("FireHurtbox") as Area2D
@onready var _detect_area: Area2D = get_node_or_null("DetectArea") as Area2D
@onready var _attack_hitbox: Area2D = get_node_or_null("AttackHitbox") as Area2D
@onready var _light_beam_hitbox: Area2D = get_node_or_null("LightBeamHitbox") as Area2D
@onready var _merge_detect_area: Area2D = get_node_or_null("MergeDetectArea") as Area2D
@onready var _mark2d: Marker2D = get_node_or_null("Mark2D") as Marker2D
@onready var _ground_raycast: RayCast2D = get_node_or_null("GroundRaycast") as RayCast2D
@onready var _body_collision: CollisionShape2D = get_node_or_null("CollisionShape2D") as CollisionShape2D

const SOUL_CLEAVER_SCENE_PATH: String = "res://scene/enemies/soul_devourer/SoulCleaver.tscn"
var _soul_cleaver_scene: PackedScene = null

# ===== 重力常量 =====
const GRAVITY: float = 1200.0


# =============================================================================
# 生命周期
# =============================================================================

func _ready() -> void:
	species_id = &"soul_devourer"
	entity_type = EntityType.MONSTER
	attribute_type = AttributeType.DARK
	size_tier = SizeTier.MEDIUM
	max_hp = 5
	hp = 5
	weak_hp = 1
	hit_stun_time = 0.0
	stun_duration = 0.0
	healing_burst_stun_time = 0.0

	# LightReceiver 与 FireHurtbox 分离
	light_receiver_path = NodePath("LightReceiver")

	super._ready()
	add_to_group("chain_passthrough")  # 链条穿过 SD（on_chain_hit 恒返回 0）

	_spawn_point = global_position

	# 预加载 SoulCleaver 场景
	if ResourceLoader.exists(SOUL_CLEAVER_SCENE_PATH):
		_soul_cleaver_scene = load(SOUL_CLEAVER_SCENE_PATH) as PackedScene

	# 初始化动画驱动
	if _is_spine_compatible(_spine_sprite):
		_anim_driver = AnimDriverSpine.new()
		add_child(_anim_driver)
		_anim_driver.setup(_spine_sprite)
		_anim_driver.anim_completed.connect(_on_anim_completed)
		if _spine_sprite.has_signal("animation_event"):
			_spine_sprite.animation_event.connect(_on_spine_animation_event)
	else:
		_anim_mock = AnimDriverMock.new()
		add_child(_anim_mock)
		_anim_mock.anim_completed.connect(_on_anim_completed)

	if _attack_hitbox != null and not _attack_hitbox.body_entered.is_connected(_on_attack_hitbox_body_entered):
		_attack_hitbox.body_entered.connect(_on_attack_hitbox_body_entered)
	if _light_beam_hitbox != null and not _light_beam_hitbox.body_entered.is_connected(_on_light_beam_hitbox_body_entered):
		_light_beam_hitbox.body_entered.connect(_on_light_beam_hitbox_body_entered)

	# 初始状态
	_set_attack_hitbox_enabled(false)
	_set_light_beam_hitbox_enabled(false)
	_set_fire_hurtbox_enabled(true)
	anim_play(&"normal/idle", true)


func _is_spine_compatible(node: Node) -> bool:
	if node == null:
		return false
	if String(node.get_class()) == "SpineSprite":
		return true
	return node.has_method("get_animation_state")


func _physics_process(dt: float) -> void:
	# 光照系统 tick（继承自 MonsterBase）
	if light_counter > 0.0:
		light_counter -= dt
		light_counter = max(light_counter, 0.0)
	_thunder_processed_this_frame = false

	# 近期伤害追踪
	if _recent_damage_timer > 0.0:
		_recent_damage_timer -= dt
		if _recent_damage_timer <= 0.0:
			_recent_damage_timer = 0.0
			_recent_damage_amount = 0.0

	# Mock 驱动 tick
	if _anim_mock:
		_anim_mock.tick(dt)

	# 同步 FireHurtbox 骨骼位置
	_sync_fire_hurtbox()

	# death-rebirth 隐藏期：不做任何物理处理
	if _is_dead_hidden or _is_respawning:
		return

	# Hurt 僵直计时
	if _hurt_active:
		_hurt_timer -= dt
		velocity.x = 0.0
		if _hurt_timer <= 0.0:
			_hurt_active = false
			_hurt_timer = 0.0

	# 重力（仅显现态落地时）
	if not _is_floating_invisible and not _forced_invisible:
		if _landing_locked:
			pass  # 着陆期间由 act_landing_sequence 控制物理
		else:
			if not is_on_floor():
				velocity.y += GRAVITY * dt
			else:
				velocity.y = max(velocity.y, 0.0)
			move_and_slide()
	else:
		# 漂浮隐身态：无重力，action 直接设置 velocity
		move_and_slide()

	# 不调用 super._physics_process()：
	# MonsterBase 的 weak/stun 系统由 death-rebirth 替代。
	# BeehaveTree 的 tick 由其自身 _physics_process 驱动。

	# === 采样状态日志（每 120 帧 ≈ 2 秒一次）===
	if Engine.get_physics_frames() % 120 == 0:
		print("[SD] state: hp=%d aggro=%s full=%s knife=%s float=%s forced=%s land=%s anim=%s vel=%s" % [
			hp, _aggro_mode, _is_full, _has_knife,
			_is_floating_invisible, _forced_invisible, _landing_locked,
			_current_anim, velocity])


# =============================================================================
# 动画播放接口
# =============================================================================

func anim_play(anim_name: StringName, loop: bool) -> bool:
	# Hurt 僵直期间不允许行为树覆写动画（仅内部 _force_anim_play 可绕过）
	if _hurt_active:
		return false
	_force_anim_play(anim_name, loop)
	return true


## 内部用：绕过 hurt 锁定强制播放动画
func _force_anim_play(anim_name: StringName, loop: bool) -> void:
	if _current_anim == anim_name and not _current_anim_finished and _current_anim_loop == loop:
		return
	_current_anim = anim_name
	_current_anim_finished = false
	_current_anim_loop = loop
	if _anim_driver:
		_anim_driver.play(0, anim_name, loop, AnimDriverSpine.PlayMode.REPLACE_TRACK)
	elif _anim_mock:
		_anim_mock.play(0, anim_name, loop)


func anim_is_playing(anim_name: StringName) -> bool:
	return _current_anim == anim_name and not _current_anim_finished


func anim_is_finished(anim_name: StringName) -> bool:
	return _current_anim == anim_name and _current_anim_finished


func _on_anim_completed(_track: int, anim_name: StringName) -> void:
	if anim_name == _current_anim:
		_current_anim_finished = true


# ===== 双文件夹前缀辅助 =====

func _get_anim_prefix() -> String:
	return "has_knife/" if _has_knife else "normal/"


func anim_play_prefixed(anim_base: StringName, loop: bool) -> void:
	anim_play(StringName(_get_anim_prefix() + String(anim_base)), loop)


# =============================================================================
# 骨骼跟随
# =============================================================================

func _sync_fire_hurtbox() -> void:
	if _fire_hurtbox == null:
		return
	if _anim_driver == null:
		return
	var bone_pos: Vector2 = Vector2.ZERO
	if _spine_sprite != null:
		if _spine_sprite.has_method("get_global_bone_transform"):
			var xform: Transform2D = _spine_sprite.call("get_global_bone_transform", "fire")
			if xform != Transform2D.IDENTITY:
				bone_pos = xform.origin
		elif _spine_sprite.has_method("get_skeleton"):
			var sk = _spine_sprite.call("get_skeleton")
			if sk != null:
				var bone = null
				if sk.has_method("find_bone"):
					bone = sk.call("find_bone", "fire")
				elif sk.has_method("findBone"):
					bone = sk.call("findBone", "fire")
				if bone != null:
					var wx: float = 0.0
					var wy: float = 0.0
					if bone.has_method("get_world_x"):
						wx = float(bone.call("get_world_x"))
						wy = float(bone.call("get_world_y"))
					elif bone.has_method("getWorldX"):
						wx = float(bone.call("getWorldX"))
						wy = float(bone.call("getWorldY"))
					if wx != 0.0 or wy != 0.0:
						bone_pos = Vector2(wx, -wy)  # Spine Y 轴取反
	if bone_pos != Vector2.ZERO:
		_fire_hurtbox.position = to_local(bone_pos)


# =============================================================================
# 命中入口（FIX-V5-01）
# =============================================================================

func on_chain_hit(_player: Node, _slot: int) -> int:
	## 全状态不可 chain
	return 0


func apply_stun(_seconds: float, _do_flash: bool = true) -> void:
	## 无 stun
	return


func apply_hit(hit: HitData) -> bool:
	if hit == null:
		return false
	if _death_rebirth_started:
		print("[SD] apply_hit REJECTED: death_rebirth in progress")
		return false
	if hit.weapon_id != &"ghost_fist":
		print("[SD] apply_hit REJECTED: weapon=%s (need ghost_fist)" % hit.weapon_id)
		return false

	# 有效命中（必然是 FireHurtbox，因为没有身体 Hurtbox）
	var old_hp: int = hp
	_aggro_mode = true
	hp = max(hp - hit.damage, 0)
	_flash_once()
	print("[SD] apply_hit OK: hp=%d→%d, aggro=%s, dmg=%d, anim=%s" % [old_hp, hp, _aggro_mode, hit.damage, _current_anim])

	# Hurt 受击僵直：仅 idle/run 状态可被打断
	if _is_in_hurtable_anim() and not _hurt_active:
		_hurt_active = true
		_hurt_timer = HURT_STUN_DURATION
		var hurt_anim: StringName = StringName(_get_anim_prefix() + "hurt")
		_force_anim_play(hurt_anim, false)
		velocity.x = 0.0
		print("[SD] HURT triggered: anim=%s, stun=%.2fs" % [hurt_anim, HURT_STUN_DURATION])

	# 近期伤害追踪（用于强制隐身条件）
	_recent_damage_amount += float(hit.damage)
	_recent_damage_timer = RECENT_DAMAGE_WINDOW

	if hp <= weak_hp:
		if _landing_locked:
			_pending_death_rebirth = true
			print("[SD] death-rebirth PENDING (landing locked)")
		else:
			print("[SD] → entering death-rebirth flow")
			_enter_death_rebirth_flow()
	return true


func _update_weak_state() -> void:
	## 默认不覆写基类 weak 链路；death-rebirth 的唯一入口在 apply_hit()。
	## 如联调确认基类 weak 链路仍有副作用，取消注释下面的 pass 覆写。
	pass  # 噬魂犬不走基类 weak 链路


# =============================================================================
# Death-Rebirth 流程
# =============================================================================

func _enter_death_rebirth_flow() -> void:
	if _death_rebirth_started:
		return  # 防重入
	_death_rebirth_started = true

	# 强制解除 hurt 僵直（否则 anim_play 被锁定，死亡动画无法播放）
	_hurt_active = false
	_hurt_timer = 0.0

	# 释放刀引用（无论 cleaver_pick 是否已触发都安全清空）
	_current_target_cleaver = null

	# 锁死行为树
	var bt: Node = get_node_or_null("BeehaveTree")
	if bt != null and bt.has_method("disable"):
		bt.call("disable")

	# 关闭攻击
	_set_attack_hitbox_enabled(false)
	_set_light_beam_hitbox_enabled(false)

	# 停止移动
	velocity = Vector2.ZERO

	# 若持刀：先播放 has_knife/weak，Spine 事件 spawn_cleaver 生成刀
	if _has_knife:
		anim_play(&"has_knife/weak", false)
		# 等待 animation_completed 在 _on_death_rebirth_anim_completed 中处理
	else:
		_play_death_animation()


func _play_death_animation() -> void:
	anim_play(&"normal/death", false)


func _finish_death_and_hide() -> void:
	_is_dead_hidden = true

	# 隐藏整个节点（含所有碰撞）
	visible = false
	if _body_collision:
		_body_collision.disabled = true
	_set_fire_hurtbox_enabled(false)
	_set_attack_hitbox_enabled(false)
	_set_light_beam_hitbox_enabled(false)

	# 停止行为树
	var bt: Node = get_node_or_null("BeehaveTree")
	if bt != null and bt.has_method("disable"):
		bt.call("disable")

	# 10 秒后重生
	get_tree().create_timer(rebirth_delay).timeout.connect(_respawn_from_spawn_point)


func _respawn_from_spawn_point() -> void:
	global_position = _spawn_point
	_is_dead_hidden = false
	_is_respawning = true
	anim_play(&"normal/born", false)
	visible = true


func _reset_runtime_state_after_respawn() -> void:
	hp = max_hp
	print("[SD] RESPAWN: hp=%d, aggro=%s (kept)" % [hp, _aggro_mode])
	# _aggro_mode 不重置：蓝图规定一旦被玩家攻击进入 aggro，永久保持
	_is_full = false
	_hunt_succeed_playing = false
	_has_knife = false
	_pickup_anim_playing = false
	_is_floating_invisible = false
	_forced_invisible = false
	_death_rebirth_started = false
	_is_dead_hidden = false
	_is_respawning = false
	_landing_locked = false
	_pending_death_rebirth = false
	_merging = false
	_force_separate = false
	_current_target_ghost = null
	_current_target_cleaver = null
	_knife_attack_count = 0
	_hurt_active = false
	_hurt_timer = 0.0
	velocity = Vector2.ZERO

	# 恢复碰撞
	if _body_collision:
		_body_collision.disabled = false
	_set_fire_hurtbox_enabled(true)

	# 恢复 collision_mask（World 层）
	collision_mask = 1  # World(1)

	# 重启行为树
	var bt: Node = get_node_or_null("BeehaveTree")
	if bt != null:
		if bt.has_method("interrupt"):
			bt.call("interrupt")
		if bt.has_method("enable"):
			bt.call("enable")

	anim_play(&"normal/idle", true)


# =============================================================================
# 着陆序列
# =============================================================================

func _on_landing_complete() -> void:
	_landing_locked = false
	if _pending_death_rebirth:
		_pending_death_rebirth = false
		_enter_death_rebirth_flow()


# =============================================================================
# 显隐系统
# =============================================================================

func _enter_floating_invisible() -> void:
	_is_floating_invisible = true
	# 隐身时清除 World 层（悬浮）
	collision_mask = 0  # 不与地面碰撞
	# 停止重力
	velocity = Vector2.ZERO


func _exit_floating_invisible_to_landing(remaining_light_time: float) -> void:
	_is_floating_invisible = false
	# 恢复 World 层碰撞
	collision_mask = 1  # World(1)
	# 触发着陆序列（fall_loop → GroundRaycast → fall_down）
	_landing_locked = true
	anim_play(&"normal/fall_loop", true)
	# remaining_light_time 可用于 visible_time 计算（此处保留接口）
	if remaining_light_time <= 0.0:
		pass  # 自然着陆


func _enter_forced_invisible() -> void:
	_forced_invisible = true
	_is_floating_invisible = true
	collision_mask = 0
	velocity = Vector2.ZERO
	anim_play(&"normal/forced_invisible", false)


## 强制隐身覆写基类光照接口（FIX-V5-02）
func _on_thunder_burst(add_seconds: float) -> void:
	if _forced_invisible:
		return  # thunder 不能打断强制隐身
	super._on_thunder_burst(add_seconds)


func on_light_exposure(remaining_time: float, source: Node = null) -> void:
	if _forced_invisible:
		# 强制隐身期间仅 LightningFlower 来源可解除
		if source != null and source.get_class() == "LightningFlower":
			_forced_invisible = false
			_is_floating_invisible = false
			_exit_floating_invisible_to_landing(remaining_time)
		# 非 LightningFlower 来源：忽略
		return
	# 能量获取是普通光照怪物的 2 倍
	light_counter += remaining_time * 2.0
	light_counter = min(light_counter, light_counter_max)


## 朝向辅助（仅翻转 SpineSprite，含 10px 死区防抖）
## 判断当前动画是否允许被 hurt 打断（仅 idle/run）
func _is_in_hurtable_anim() -> bool:
	var anim: String = String(_current_anim)
	return anim.ends_with("/idle") or anim.ends_with("/run")


func face_toward_position(target_x: float) -> void:
	var dx: float = target_x - global_position.x
	if absf(dx) <= FACE_DEAD_ZONE:
		return
	var sign_x: float = 1.0 if dx > 0.0 else -1.0
	if _spine_sprite != null:
		_spine_sprite.scale.x = absf(_spine_sprite.scale.x) * sign_x


func face_toward(target: Node2D) -> void:
	if target == null:
		return
	face_toward_position(target.global_position.x)


# =============================================================================
# 目标查找
# =============================================================================

func _find_nearest_huntable_ghost() -> Node2D:
	var ghosts := get_tree().get_nodes_in_group("huntable_ghost")
	var nearest: Node2D = null
	var nearest_dist: float = INF
	for g in ghosts:
		if not is_instance_valid(g):
			continue
		var n: Node2D = g as Node2D
		if n == null:
			continue
		# 过滤：可见 + 非 dying + 非 being_hunted
		if n.has_method("is_being_hunted") and bool(n.call("is_being_hunted")):
			continue
		if n.has_method("is_dying") and bool(n.call("is_dying")):
			continue
		if n.has_method("is_ghost_visible") and not bool(n.call("is_ghost_visible")):
			continue
		var d: float = global_position.distance_to(n.global_position)
		if d < nearest_dist:
			nearest_dist = d
			nearest = n
	return nearest


func _find_nearest_cleaver() -> SoulCleaver:
	var cleavers := get_tree().get_nodes_in_group("soul_cleaver")
	var best: SoulCleaver = null
	var best_dist: float = INF
	var self_id: int = get_instance_id()
	# 优先选自己掉的刀（owner_instance_id 匹配）
	for c in cleavers:
		if not is_instance_valid(c):
			continue
		var cleaver: SoulCleaver = c as SoulCleaver
		if cleaver == null:
			continue
		if cleaver.claimed and cleaver.owner_instance_id != self_id:
			continue
		var d: float = global_position.distance_to(cleaver.global_position)
		if cleaver.owner_instance_id == self_id:
			# 优先权：自己掉的刀权重更高
			d -= 9999.0
		if d < best_dist:
			best_dist = d
			best = cleaver
	return best


func _is_huntable_ghost_valid(target: Node) -> bool:
	if not is_instance_valid(target):
		return false
	if target.has_method("is_being_hunted") and bool(target.call("is_being_hunted")):
		return false
	if target.has_method("is_dying") and bool(target.call("is_dying")):
		return false
	if target.has_method("is_ghost_visible") and not bool(target.call("is_ghost_visible")):
		return false
	return true


# =============================================================================
# Hitbox 开关
# =============================================================================

func _set_attack_hitbox_enabled(enabled: bool) -> void:
	if _attack_hitbox == null:
		return
	_attack_hitbox.set_deferred("monitoring", enabled)
	_attack_hitbox.set_deferred("monitorable", enabled)
	var cs: CollisionShape2D = _attack_hitbox.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if cs:
		cs.set_deferred("disabled", not enabled)


func _set_light_beam_hitbox_enabled(enabled: bool) -> void:
	if _light_beam_hitbox == null:
		return
	_light_beam_hitbox.set_deferred("monitoring", enabled)
	_light_beam_hitbox.set_deferred("monitorable", enabled)
	var cs: CollisionShape2D = _light_beam_hitbox.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if cs:
		cs.set_deferred("disabled", not enabled)


func _set_fire_hurtbox_enabled(enabled: bool) -> void:
	if _fire_hurtbox == null:
		return
	# FireHurtbox 是被动 Hurtbox：monitorable 控制能否被检测到
	_fire_hurtbox.set_deferred("monitorable", enabled)
	var cs: CollisionShape2D = _fire_hurtbox.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if cs:
		cs.set_deferred("disabled", not enabled)


func _on_attack_hitbox_body_entered(body: Node2D) -> void:
	_deal_damage_to_player(body, 1, "knife")


func _on_light_beam_hitbox_body_entered(body: Node2D) -> void:
	_deal_damage_to_player(body, 1, "light_beam")


func _deal_damage_to_player(body: Node2D, amount: int, source: String) -> void:
	if body == null or amount <= 0:
		return
	if not body.has_method("apply_damage"):
		return
	body.call("apply_damage", amount, global_position)
	print("[SD] HIT PLAYER via %s: amount=%d player=%s source_pos=%s" % [
		source, amount, body.name, global_position])


# =============================================================================
# Spine 事件回调
# =============================================================================

func _on_spine_animation_event(a1, a2, a3, a4) -> void:
	# 兼容 Spine Godot 不同签名的事件回调
	var spine_event: Object = null
	for a in [a1, a2, a3, a4]:
		if a is Object and a.has_method("get_data"):
			spine_event = a
			break
	if spine_event == null:
		return

	var data = spine_event.get_data()
	if data == null:
		return

	var event_name: StringName = &""
	if data.has_method("get_event_name"):
		event_name = StringName(data.get_event_name())
	elif data.has_method("getName"):
		event_name = StringName(data.call("getName"))
	if event_name == &"":
		return

	match event_name:
		&"atk_hit_on":
			_set_attack_hitbox_enabled(true)
		&"atk_hit_off":
			_set_attack_hitbox_enabled(false)
		&"cleaver_pick":
			_on_spine_event_cleaver_pick()
		&"throw_cleaver":
			_on_spine_event_throw_cleaver()
		&"spawn_cleaver":
			_on_spine_event_spawn_cleaver()


func _on_spine_event_cleaver_pick() -> void:
	## cleaver_pick：立即销毁目标 SoulCleaver（刀已进入噬魂犬动画表现）
	if _current_target_cleaver == null:
		return
	if is_instance_valid(_current_target_cleaver):
		_current_target_cleaver.queue_free()
	_current_target_cleaver = null
	# 持刀视觉从此帧开始成立
	# _has_knife = true 等 animation_completed 后在行为树中设置


func _on_spine_event_throw_cleaver() -> void:
	## throw_cleaver：甩出刀，生成新 SoulCleaver，关闭持刀视觉
	if _soul_cleaver_scene == null:
		return
	var cleaver: SoulCleaver = (_soul_cleaver_scene as PackedScene).instantiate() as SoulCleaver
	if cleaver == null:
		return
	var spawn_pos: Vector2 = global_position
	if _mark2d:
		spawn_pos = _mark2d.global_position
	cleaver.global_position = spawn_pos
	cleaver.owner_instance_id = get_instance_id()
	# 赋予抛出初速度（基于 SpineSprite 朝向，不读 CharacterBody2D scale）
	var facing: float = 1.0
	if _spine_sprite != null and _spine_sprite.scale.x != 0.0:
		facing = sign(_spine_sprite.scale.x)
	cleaver.velocity = Vector2(facing * 200.0, -80.0)
	get_parent().add_child(cleaver)
	# 关闭持刀视觉，_has_knife 在事件帧置 false
	_has_knife = false


func _on_spine_event_spawn_cleaver() -> void:
	## spawn_cleaver：受击掉刀（has_knife/weak 动画中）
	if _soul_cleaver_scene == null:
		return
	var cleaver: SoulCleaver = (_soul_cleaver_scene as PackedScene).instantiate() as SoulCleaver
	if cleaver == null:
		return
	var spawn_pos: Vector2 = global_position
	if _mark2d:
		spawn_pos = _mark2d.global_position
	cleaver.global_position = spawn_pos
	cleaver.owner_instance_id = get_instance_id()
	get_parent().add_child(cleaver)


# =============================================================================
# Death-Rebirth 动画回调（由行为树 act_death_rebirth_flow 调用检测）
# =============================================================================

## 供 act_death_rebirth_flow 调用：判断是否应播放 death 动画
func death_rebirth_should_play_knife_weak() -> bool:
	return _has_knife and _death_rebirth_started


## 供 act_death_rebirth_flow 调用：进入 born 完成后的重置
func death_rebirth_on_born_finished() -> void:
	_reset_runtime_state_after_respawn()


# =============================================================================
# 合体机制辅助
# =============================================================================

func _get_merge_partner() -> SoulDevourer:
	## 查找场上另一只漂浮隐身的 SoulDevourer
	var all: Array = get_tree().get_nodes_in_group("monster")
	for m in all:
		if m == self:
			continue
		if not is_instance_valid(m):
			continue
		var other: SoulDevourer = m as SoulDevourer
		if other == null:
			continue
		if other._is_floating_invisible and not other._merging and not other._death_rebirth_started:
			return other
	return null


func _can_initiate_merge() -> bool:
	## 实例 ID 较小者发起合体
	var partner: SoulDevourer = _get_merge_partner()
	if partner == null:
		return false
	return get_instance_id() < partner.get_instance_id()


static func now_sec() -> float:
	return Time.get_ticks_msec() / 1000.0
