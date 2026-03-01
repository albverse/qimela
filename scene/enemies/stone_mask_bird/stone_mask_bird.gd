extends MonsterBase
class_name StoneMaskBird

## =============================================================================
## StoneMaskBird - 石面鸟（Beehave x Spine 行为树怪物）
## =============================================================================
## 飞行攻击型怪物。休息->唤醒->飞行冲刺攻击->受击/眩晕->回巢->休息循环。
## 行为由 Beehave 行为树驱动，动画由 AnimDriverSpine 驱动。
## =============================================================================

# ===== Mode 枚举（高层模式）=====
enum Mode {
	RESTING = 0,          ## 倒地休息
	WAKING = 1,           ## 唤醒（0.5s，不可打断）
	FLYING_ATTACK = 2,    ## 飞行攻击循环（含追击子状态）
	RETURN_TO_REST = 3,   ## 回巢倒地
	STUNNED = 4,          ## 眩晕（坠落->触地->地面眩晕）
	WAKE_FROM_STUN = 5,   ## 从眩晕苏醒
	HURT = 6,             ## 飞行受击
	REPAIRING = 7,        ## 正在修复 rest_area_break
	HUNTING = 8,          ## 狩猎 walk_monster 以获取面具
}

# ===== StoneMaskBird 可调参数（策划可改）=====

@export var stun_duration_sec: float = 2.0
## 眩晕持续时间（秒）。触发方式：雷花/健康精灵爆炸/或 HP<=1 时。

@export var dash_speed: float = 1000.0
## 冲刺速度（px/s）。决定"极快"的体感。建议范围：900~1200。

@export var attack_offset_y: float = 90.0
## 攻击时悬停点的垂直偏移（px）。目标点 = player.position + Vector2(0, -attack_offset_y)。

@export var return_speed: float = 450.0
## 回巢速度（px/s）。

@export var reach_rest_px: float = 30.0
## 到达休息点判定阈值（px）。

@export var hurt_duration: float = 0.2
## 受击持续时间（秒）。

@export var hurt_knockback_px: float = 40.0
## 受击击退距离（px）。

@export var fall_gravity: float = 600.0
## 眩晕坠落重力加速度（px/s^2）。

@export var hover_speed: float = 300.0
## 飞行悬停移动速度（px/s），飞向 hover_point 时使用。

@export var attack_duration_sec: float = 60.0
## 每次唤醒后的攻击持续时间（秒）。

@export var dash_cooldown: float = 0.5
## 冲刺攻击间隔（秒）。

@export var attack_range_px: float = 200.0
## 攻击范围（px）。AttackArea 半径与此值匹配。玩家在此范围内才执行 ActAttackLoopDash。

@export var chase_range_px: float = 200.0
## 追击感知范围（px）。玩家在此范围内时执行飞行追击（fly_move）。

@export var hunt_speed: float = 250.0
## 狩猎飞行速度（px/s）。飞向 walk_monster 时使用。

@export var hunt_range_px: float = 400.0
## 狩猎感知范围（px）。walk_monster 在此范围内时才会飞过去狩猎。

@export var rest_hunt_trigger_px: float = 100.0
## RESTING 时发现 MonsterWalk 的触发范围（px）。

@export var hunt_cooldown_sec: float = 5.0
## 每次成功狩猎后的冷却时间（秒）。冷却中不能再次进入 HUNTING。

@export var face_shoot_range_px: float = 200.0
## has_face 发射面具弹的触发范围（px）。

@export var face_hover_offset: Vector2 = Vector2(100.0, -100.0)
## has_face 发射前悬停偏移（相对玩家坐标）。

@export var face_bullet_speed: float = 240.0
## 面具弹飞行速度（px/s）。

@export var face_bullet_texture: Texture2D = preload("res://icon.svg")
## 面具弹贴图（可在 Inspector 中替换材质/图片）。

# ===== 内部状态（BT 叶节点直接读写）=====

var mode: int = Mode.RESTING

## 唤醒结束时写入 now + attack_duration_sec
var attack_until_sec: float = 0.0

## 下一次冲刺的时间戳（间隔由 dash_cooldown 决定）
var next_attack_sec: float = 0.0

## 眩晕结束时间
var stun_until_sec: float = 0.0

## 受击结束时间
var hurt_until_sec: float = 0.0

## 一次冲刺的起点（冲出去再冲回来）
var dash_origin: Vector2 = Vector2.ZERO

## 选中的 rest_area（Marker2D）
var target_rest: Node2D = null

## 正在修复的 rest_area_break 节点（REPAIRING 模式下使用）
var target_repair_area: Node2D = null

## 面具状态：true=有面具（可发射），false=无面具（项目原始状态）
var has_face: bool = false

## 狩猎目标（HUNTING 模式下使用）
var hunt_target: Node2D = null

## shoot_face 动画中 shoot 事件是否已触发（由 Spine 事件回调写入）
var face_shoot_event_fired: bool = false

## act_shoot_face 已锁定发射意图：BT 条件节点在此期间始终返回 SUCCESS，
## 防止玩家离开检测范围或 has_face 变 false 导致动画被中途打断。
## 由 ActShootFace.before_run() 置 true，interrupt()/完成后置 false。
var shoot_face_committed: bool = false

## 休息态触发的狩猎请求：wake_up 结束后直接进入 HUNTING
var rest_hunt_requested: bool = false

## HUNTING 中被控制暂停的目标（用于中断时恢复）
var hunt_paused_target: Node2D = null

## 下一次允许进入 HUNTING 的时间戳（秒）
var next_hunt_allowed_sec: float = 0.0

@onready var _shoot_point: Marker2D = get_node_or_null("ShootPoint") as Marker2D

# ===== 动画状态追踪 =====

var _current_anim: StringName = &""
var _current_anim_resolved: StringName = &""
var _current_anim_finished: bool = false
var _current_anim_loop: bool = false
var _current_interruptible: bool = true
var _current_anim_started_sec: float = -1.0

const _HAS_FACE_ANIMS: Dictionary = {
	&"fall_loop": true,
	&"fix_rest_area_loop": true,
	&"fly_idle": true,
	&"fly_move": true,
	&"hurt": true,
	&"land": true,
	&"rest_loop": true,
	&"shoot_face": true,
	&"sleep_down": true,
	&"stun_loop": true,
	&"takeoff": true,
	&"wake_from_stun": true,
	&"wake_up": true,
}

const _NO_FACE_ANIMS: Dictionary = {
	&"dash_attack": true,
	&"dash_return": true,
	&"fall_loop": true,
	&"fix_rest_area_loop": true,
	&"fly_idle": true,
	&"fly_move": true,
	&"hunting": true,
	&"hurt": true,
	&"land": true,
	&"no_face_to_has_face": true,
	&"rest_loop": true,
	&"sleep_down": true,
	&"stun_loop": true,
	&"takeoff": true,
	&"wake_from_stun": true,
	&"wake_up": true,
}

# Spine 动画驱动（优先 SpineSprite → AnimDriverSpine；无 Spine 时 → AnimDriverMock）
var _anim_driver: AnimDriverSpine = null
var _anim_mock: AnimDriverMock = null
@onready var _spine_sprite: Node = null

## 攻击范围 Area2D（石面鸟.tscn 中的 AttackArea 子节点）
## collision_mask = 2（PlayerBody），用于判断玩家是否进入攻击射程
@onready var _attack_area: Area2D = get_node_or_null("AttackArea")

# ===== 生命周期 =====

func _ready() -> void:
	species_id = &"stone_mask_bird"
	attribute_type = AttributeType.DARK
	size_tier = SizeTier.MEDIUM
	max_hp = 3
	weak_hp = 1   # 与其他怪物一致：HP<=1 进入 weak（锁血），并走 STUNNED 演出
	vanish_fusion_required = 1

	super._ready()
	add_to_group("flying_monster")

	# 初始化动画驱动：有 SpineSprite 用 AnimDriverSpine，否则用 AnimDriverMock
	_spine_sprite = get_node_or_null("SpineSprite")
	if _spine_sprite and _spine_sprite.get_class() == "SpineSprite":
		_anim_driver = AnimDriverSpine.new()
		add_child(_anim_driver)
		_anim_driver.setup(_spine_sprite)
		_anim_driver.anim_completed.connect(_on_anim_completed)
		# 连接 Spine 事件信号（用于 shoot_face 动画的 shoot 事件）
		if _spine_sprite.has_signal("animation_event"):
			_spine_sprite.animation_event.connect(_on_spine_animation_event)
	else:
		# 无 Spine 资源时使用 Mock 驱动，保证 BT 动画完成回调正常触发
		_anim_mock = AnimDriverMock.new()
		_setup_mock_durations()
		add_child(_anim_mock)
		_anim_mock.anim_completed.connect(_on_anim_completed)


func _physics_process(dt: float) -> void:
	# --- 光照系统更新（保留 MonsterBase 的光照逻辑）---
	if light_counter > 0.0:
		light_counter -= dt
		light_counter = max(light_counter, 0.0)
	_thunder_processed_this_frame = false

	# Mock 驱动需要手动 tick 来推进动画倒计时
	if _anim_mock:
		_anim_mock.tick(dt)

	# weak 倒计时（与 MonsterBase 语义保持一致：恢复后转入 WAKE_FROM_STUN 定制流程）
	if weak and weak_stun_t > 0.0:
		weak_stun_t = max(weak_stun_t - dt, 0.0)
		if weak_stun_t <= 0.0:
			_restore_from_weak()
			mode = Mode.WAKE_FROM_STUN

	# 唤醒方式：只有 ghost_fist 的 apply_hit() 才能触发 RESTING → WAKING。
	# 不做玩家接近自动唤醒。

	# 不调用 super._physics_process()：
	# MonsterBase 的 weak/stunned_t 系统由我们自己的 mode 系统替代。
	# BeehaveTree 的 tick 由其自身 _physics_process 驱动，无需此处干预。


# 不使用 MonsterBase._do_move，移动完全由 BT 叶节点控制
func _do_move(_dt: float) -> void:
	pass


# =============================================================================
# 动画播放接口（供 BT 叶节点统一调用）
# =============================================================================

func anim_play(anim_name: StringName, loop: bool, interruptible: bool) -> void:
	## 播放指定动画。BT 叶节点只调这一个接口，不直接碰 Spine。
	var resolved_anim: StringName = _resolve_anim_name(anim_name)
	# 避免在同一动画已播放中时重复 set_animation 导致重启（影响不可打断动作完成判定）。
	if _current_anim == anim_name and _current_anim_resolved == resolved_anim and not _current_anim_finished and _current_anim_loop == loop:
		return

	_current_anim = anim_name
	_current_anim_resolved = resolved_anim
	_current_anim_finished = false
	_current_anim_loop = loop
	_current_interruptible = interruptible
	_current_anim_started_sec = now_sec()
	if _anim_driver:
		_anim_driver.play(0, resolved_anim, loop, AnimDriverSpine.PlayMode.REPLACE_TRACK)
	elif _anim_mock:
		_anim_mock.play(0, resolved_anim, loop)


func anim_is_playing(anim_name: StringName) -> bool:
	return _current_anim == anim_name and not _current_anim_finished


func anim_is_finished(anim_name: StringName) -> bool:
	return _current_anim == anim_name and _current_anim_finished


func anim_stop_or_blendout() -> void:
	_current_anim = &""
	_current_anim_resolved = &""
	_current_anim_finished = true
	_current_anim_started_sec = -1.0
	if _anim_driver:
		_anim_driver.stop_all()
	elif _anim_mock:
		_anim_mock.stop(0)


func _on_anim_completed(_track: int, anim_name: StringName) -> void:
	if anim_name == _current_anim_resolved:
		_current_anim_finished = true


func _resolve_anim_name(anim_name: StringName) -> StringName:
	var anim_str := String(anim_name)
	if anim_str.contains("/"):
		return anim_name

	var logical_name: StringName = anim_name
	if logical_name == &"hunt":
		logical_name = &"hunting"

	if logical_name == &"no_face_to_has_face":
		return StringName("no_face/%s" % String(logical_name))

	if has_face and _HAS_FACE_ANIMS.has(logical_name):
		return StringName("has_face/%s" % String(logical_name))
	if not has_face and _NO_FACE_ANIMS.has(logical_name):
		return StringName("no_face/%s" % String(logical_name))
	if _HAS_FACE_ANIMS.has(logical_name):
		return StringName("has_face/%s" % String(logical_name))
	if _NO_FACE_ANIMS.has(logical_name):
		return StringName("no_face/%s" % String(logical_name))
	return anim_name


func find_nearest_walk_monster_in_range(radius_px: float) -> Node2D:
	var monsters := get_tree().get_nodes_in_group("monster")
	for n in monsters:
		if not is_instance_valid(n):
			continue
		if not (n is MonsterWalk or n is MonsterWalkB):
			continue
		var m := n as Node2D
		if m == null:
			continue
		if global_position.distance_to(m.global_position) <= radius_px:
			return m
	return null


func freeze_hunt_target(target: Node2D) -> void:
	if target == null or not is_instance_valid(target):
		return
	hunt_paused_target = target
	target.set_physics_process(false)
	target.set_process(false)
	if "velocity" in target:
		target.set("velocity", Vector2.ZERO)


func unfreeze_hunt_target() -> void:
	if hunt_paused_target != null and is_instance_valid(hunt_paused_target):
		hunt_paused_target.set_physics_process(true)
		hunt_paused_target.set_process(true)
	hunt_paused_target = null


func spawn_face_bullet(player: Node2D) -> void:
	if player == null:
		return
	var bullet := StoneMaskBirdFaceBullet.new()
	bullet.name = "FaceBullet"
	bullet.collision_layer = 0
	bullet.collision_mask = 2

	var sprite := Sprite2D.new()
	sprite.texture = face_bullet_texture if face_bullet_texture != null else preload("res://icon.svg")
	sprite.scale = Vector2(0.2, 0.2)
	bullet.add_child(sprite)

	var collision := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 8.0
	collision.shape = shape
	bullet.add_child(collision)

	var start_pos := global_position
	if _shoot_point != null:
		start_pos = _shoot_point.global_position
	bullet.global_position = start_pos

	var dir := (player.global_position - start_pos).normalized()
	bullet.setup(dir, face_bullet_speed, player)
	get_parent().add_child(bullet)


func _on_spine_animation_event(a1, a2, a3, a4) -> void:
	## Spine animation_event 信号回调。参数数量/顺序因版本而异，
	## 按 SPINE_GODOT_LATEST_INTEGRATED_STANDARD 要求：遍历找到含 get_data() 的对象。
	var spine_event: Object = null
	for a in [a1, a2, a3, a4]:
		if a is Object and a.has_method("get_data"):
			spine_event = a
			break
	if spine_event == null:
		return
	var event_name: StringName = &""
	var data = spine_event.get_data()
	if data != null and data.has_method("get_event_name"):
		event_name = StringName(data.get_event_name())
	if event_name == &"":
		return
	# shoot_face 动画中的 shoot 事件：面具脱落
	if event_name == &"shoot" and _current_anim == &"shoot_face":
		face_shoot_event_fired = true


func anim_debug_state() -> Dictionary:
	return {
		"name": _current_anim,
		"finished": _current_anim_finished,
		"loop": _current_anim_loop,
		"started_sec": _current_anim_started_sec,
	}


func _enter_weak_stunned() -> void:
	# 与其它怪一致：进入 weak 后锁血，不会继续被打到死亡；并切 STUNNED 演出。
	hp = max(hp, 1)
	weak = true
	hp_locked = true
	reset_vanish_count()
	weak_stun_t = weak_stun_time
	unfreeze_hunt_target()
	mode = Mode.STUNNED


# =============================================================================
# 受击规则（核心：按 mode 判定，规格第 8 节）
# =============================================================================

func apply_hit(hit: HitData) -> bool:
	if hit == null:
		return false
	if not has_hp or hp <= 0:
		return false

	# weak 锁血期间：命中生效但不再扣血（与 MonsterBase 一致）
	if hp_locked:
		_flash_once()
		return true

	# --- RESTING：只有 ghost_fist 能唤醒，其他武器全部无效 ---
	if mode == Mode.RESTING:
		if hit.weapon_id == &"ghost_fist":
			# ghost_fist 唤醒石面鸟（不扣血，只切换模式）
			_release_target_rest()
			mode = Mode.WAKING
			_flash_once()
			return true
		# chain、雷花、其他武器对休息中的石面鸟无效
		return false

	# --- WAKING：允许扣血与闪白，但不切换 mode（不可打断） ---
	if mode == Mode.WAKING:
		hp = max(hp - hit.damage, 0)
		hp = max(hp, 1)  # clamp 到 1，不会真死
		_flash_once()
		return true

	# --- STUNNED：允许扣血与闪白，但不切换 mode ---
	if mode == Mode.STUNNED:
		hp = max(hp - hit.damage, 0)
		hp = max(hp, 1)  # clamp 到 1，不会真死
		_flash_once()
		return true

	# --- WAKE_FROM_STUN：回巢飞行途中受击会再次陷入眩晕 ---
	if mode == Mode.WAKE_FROM_STUN:
		hp = max(hp - hit.damage, 0)
		_flash_once()
		if hp <= weak_hp:
			_enter_weak_stunned()
			return true
		if _is_flying_back_to_rest():
			_enter_weak_stunned()
			return true
		hp = max(hp, 1)
		return true


	# --- Act_ShootFace 进行中：允许被普通受击打断(HURT)；weak/雷花可打断进 STUNNED，并保留 has_face ---
	if mode == Mode.FLYING_ATTACK and _current_anim == &"shoot_face":
		hp = max(hp - hit.damage, 0)
		_flash_once()
		if hp <= weak_hp:
			_enter_weak_stunned()
			return true
		if hit.weapon_id == &"lightning_flower" or hit.weapon_id == &"lightflower" or hit.weapon_id == &"healing_burst":
			_enter_weak_stunned()
			return true
		mode = Mode.HURT
		return true

	# --- HUNTING：仅 weak/stun 才打断，普通受击只闪烁/扣血 ---
	if mode == Mode.HUNTING:
		hp = max(hp - hit.damage, 0)
		_flash_once()
		if hp <= weak_hp:
			unfreeze_hunt_target()
			_enter_weak_stunned()
			return true
		if hit.weapon_id == &"lightning_flower" or hit.weapon_id == &"lightflower" or hit.weapon_id == &"healing_burst":
			unfreeze_hunt_target()
			_enter_weak_stunned()
			return true
		return true

	# --- FLYING_ATTACK / HURT：正常受击处理 ---
	hp = max(hp - hit.damage, 0)
	_flash_once()

	# HP<=1：进入 weak + STUNNED（包含 hp<=0 的情况，防止直接死亡消失）
	if hp <= weak_hp:
		_enter_weak_stunned()
		return true

	# 雷花 / 治愈精灵爆炸：强制进入 weak + STUNNED
	if hit.weapon_id == &"lightning_flower" or hit.weapon_id == &"lightflower" or hit.weapon_id == &"healing_burst":
		_enter_weak_stunned()
		return true

	# 普通飞行受击 → HURT（0.2s 击退 + 闪白）
	if mode == Mode.FLYING_ATTACK or mode == Mode.REPAIRING or mode == Mode.HUNTING:
		mode = Mode.HURT
	return true


func _is_flying_back_to_rest() -> bool:
	return _current_anim == &"fly_move" and target_rest != null and is_instance_valid(target_rest)


# =============================================================================
# 锁链交互（只有眩晕状态才能链接）
# =============================================================================

func on_chain_hit(_player: Node, _slot: int) -> int:
	# STUNNED 状态且 hp<=1 才可链接
	if mode == Mode.STUNNED and hp <= 1:
		_linked_player = _player
		return 1
	# RESTING / WAKING / WAKE_FROM_STUN：链无效
	if mode == Mode.RESTING or mode == Mode.WAKING or mode == Mode.WAKE_FROM_STUN:
		return 0
	# HUNTING：链命中只造成闪烁，不打断（除非进入 weak）
	if mode == Mode.HUNTING:
		if hp_locked:
			_flash_once()
			return 0
		hp = max(hp - 1, 0)
		_flash_once()
		if hp <= weak_hp:
			unfreeze_hunt_target()
			_enter_weak_stunned()
		return 0

	# 飞行状态：造成 1 点伤害（走本怪自定义规则，避免 EntityBase 直杀）
	if hp_locked:
		_flash_once()
		return 0
	hp = max(hp - 1, 0)
	_flash_once()
	if hp <= weak_hp:
		_enter_weak_stunned()
	elif mode == Mode.FLYING_ATTACK or mode == Mode.REPAIRING or mode == Mode.HUNTING:
		mode = Mode.HURT
	return 0


func on_chain_attached(slot: int) -> void:
	if _linked_slots.is_empty():
		if _hurtbox != null:
			_hurtbox_original_layer = _hurtbox.collision_layer
			_hurtbox.collision_layer = 0
	if not _linked_slots.has(slot):
		_linked_slots.append(slot)
	_linked_slot = slot
	# 延长眩晕时间
	if mode == Mode.STUNNED:
		stun_until_sec += weak_stun_extend_time
	_flash_once()


# =============================================================================
# 治愈精灵爆炸反应
# =============================================================================

func apply_healing_burst_stun() -> void:
	if mode == Mode.FLYING_ATTACK or mode == Mode.HURT or mode == Mode.WAKING or mode == Mode.REPAIRING or mode == Mode.HUNTING:
		_enter_weak_stunned()


func on_light_exposure(remaining_time: float) -> void:
	super.on_light_exposure(remaining_time)
	if remaining_time <= 0.0:
		return
	if weak or mode == Mode.STUNNED or mode == Mode.WAKE_FROM_STUN:
		return
	if mode == Mode.FLYING_ATTACK or mode == Mode.HURT or mode == Mode.WAKING or mode == Mode.RETURN_TO_REST or mode == Mode.REPAIRING or mode == Mode.HUNTING:
		_enter_weak_stunned()


# =============================================================================
# Mock 驱动初始化（无 Spine 时用于测试）
# =============================================================================

func _setup_mock_durations() -> void:
	## 为 AnimDriverMock 写入各动画的模拟时长，
	## 使 anim_completed 信号在正确的时间触发。
	_anim_mock._durations[&"rest_loop"] = 1.0        # loop，不会触发 completed
	_anim_mock._durations[&"wake_up"] = 0.5          # 唤醒动画 0.5s
	_anim_mock._durations[&"fly_idle"] = 0.8         # loop
	_anim_mock._durations[&"dash_attack"] = 0.3
	_anim_mock._durations[&"dash_return"] = 0.3
	_anim_mock._durations[&"fly_move"] = 0.6         # loop
	_anim_mock._durations[&"hurt"] = 0.2
	_anim_mock._durations[&"fall_loop"] = 0.5        # loop
	_anim_mock._durations[&"land"] = 0.3
	_anim_mock._durations[&"stun_loop"] = 1.0        # loop
	_anim_mock._durations[&"wake_from_stun"] = 0.5
	_anim_mock._durations[&"takeoff"] = 0.4
	_anim_mock._durations[&"sleep_down"] = 0.4
	_anim_mock._durations[&"fix_rest_area_loop"] = 1.0  # loop，修复 rest_area_break 动画
	_anim_mock._durations[&"shoot_face"] = 0.6
	_anim_mock._durations[&"hunt"] = 0.5
	_anim_mock._durations[&"no_face_to_has_face"] = 0.5


# =============================================================================
# 辅助方法
# =============================================================================

func _get_player() -> Node2D:
	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return null
	return players[0] as Node2D


## 时间基准：秒
static func now_sec() -> float:
	return Time.get_ticks_msec() / 1000.0


func can_start_hunt(now: float = -1.0) -> bool:
	if now < 0.0:
		now = now_sec()
	return now >= next_hunt_allowed_sec


func trigger_hunt_cooldown(now: float = -1.0) -> void:
	if now < 0.0:
		now = now_sec()
	next_hunt_allowed_sec = now + hunt_cooldown_sec


func face_shoot_engage_range_px() -> float:
	# 当悬停偏移距离大于 face_shoot_range_px 时，
	# 允许在“可到达悬停点”的距离内继续 ShootFace，避免 SelectorReactive 来回打断。
	return max(face_shoot_range_px, face_hover_offset.length())


func reserve_rest_area(rest_area: Node2D) -> bool:
	if rest_area == null or not is_instance_valid(rest_area):
		return false
	if not rest_area.has_method("reserve_for"):
		return false
	var ok: bool = bool(rest_area.call("reserve_for", self))
	if ok:
		target_rest = rest_area
	return ok


func release_rest_area(rest_area: Node2D) -> void:
	if rest_area == null or not is_instance_valid(rest_area):
		return
	if rest_area.has_method("release_for"):
		rest_area.call("release_for", self)


func _release_target_rest() -> void:
	if target_rest != null and is_instance_valid(target_rest):
		release_rest_area(target_rest)
	target_rest = null
