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
	FLYING_ATTACK = 2,    ## 飞行攻击循环
	RETURN_TO_REST = 3,   ## 回巢倒地
	STUNNED = 4,          ## 眩晕（坠落->触地->地面眩晕）
	WAKE_FROM_STUN = 5,   ## 从眩晕苏醒
	HURT = 6,             ## 飞行受击
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

@export var reach_rest_px: float = 24.0
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
var current_rest_area: Node = null

# ===== 动画状态追踪 =====

var _current_anim: StringName = &""
var _current_anim_finished: bool = false
var _current_anim_loop: bool = false
var _current_interruptible: bool = true
var _current_anim_deadline_sec: float = -1.0

# 单次动画的兜底时长（秒）：
# Spine 在动画名不存在/未发 completed 信号时，避免 BT 永久卡在 RUNNING。
const _ANIM_FALLBACK_DURATION := {
	&"wake_up": 0.5,
	&"dash_attack": 0.3,
	&"dash_return": 0.3,
	&"hurt": 0.2,
	&"land": 0.3,
	&"wake_from_stun": 0.5,
	&"takeoff": 0.4,
	&"sleep_down": 0.4,
}

# Spine 动画驱动（优先 SpineSprite → AnimDriverSpine；无 Spine 时 → AnimDriverMock）
var _anim_driver: AnimDriverSpine = null
var _anim_mock: AnimDriverMock = null
@onready var _spine_sprite: Node = null

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
	else:
		# 无 Spine 资源时使用 Mock 驱动，保证 BT 动画完成回调正常触发
		_anim_mock = AnimDriverMock.new()
		_setup_mock_durations()
		add_child(_anim_mock)
		_anim_mock.anim_completed.connect(_on_anim_completed)


func _exit_tree() -> void:
	release_rest_area()

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

	# Spine 兜底：一次性动画到时自动完成，防止 ActionLeaf 卡死在 RUNNING。
	if not _current_anim_finished and _current_anim_deadline_sec > 0.0 and now_sec() >= _current_anim_deadline_sec:
		_current_anim_finished = true
		_current_anim_deadline_sec = -1.0

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
	# 避免在同一动画已播放中时重复 set_animation 导致重启（影响不可打断动作完成判定）。
	if _current_anim == anim_name and not _current_anim_finished and _current_anim_loop == loop:
		return

	_current_anim = anim_name
	_current_anim_finished = false
	_current_anim_loop = loop
	_current_interruptible = interruptible
	if loop:
		_current_anim_deadline_sec = -1.0
	else:
		var duration: float = float(_ANIM_FALLBACK_DURATION.get(anim_name, 0.0))
		_current_anim_deadline_sec = now_sec() + duration if duration > 0.0 else -1.0
	if _anim_driver:
		_anim_driver.play(0, anim_name, loop, AnimDriverSpine.PlayMode.REPLACE_TRACK)
	elif _anim_mock:
		_anim_mock.play(0, anim_name, loop)


func anim_is_playing(anim_name: StringName) -> bool:
	return _current_anim == anim_name and not _current_anim_finished


func anim_is_finished(anim_name: StringName) -> bool:
	return _current_anim == anim_name and _current_anim_finished


func anim_stop_or_blendout() -> void:
	_current_anim = &""
	_current_anim_finished = true
	_current_anim_deadline_sec = -1.0
	if _anim_driver:
		_anim_driver.stop_all()
	elif _anim_mock:
		_anim_mock.stop(0)


func _on_anim_completed(_track: int, anim_name: StringName) -> void:
	if anim_name == _current_anim:
		_current_anim_finished = true
		_current_anim_deadline_sec = -1.0


func _enter_weak_stunned() -> void:
	# 与其它怪一致：进入 weak 后锁血，不会继续被打到死亡；并切 STUNNED 演出。
	hp = max(hp, 1)
	weak = true
	hp_locked = true
	reset_vanish_count()
	weak_stun_t = weak_stun_time
	mode = Mode.STUNNED
	release_rest_area()


func _enter_light_stunned() -> void:
	# 雷花光照触发普通眩晕（不强制改成 weak），由 Act_StunnedFallLoop 走 stun_duration_sec。
	if mode == Mode.STUNNED:
		return
	mode = Mode.STUNNED
	release_rest_area()


func on_light_exposure(remaining_time: float) -> void:
	super.on_light_exposure(remaining_time)
	if remaining_time <= 0.0:
		return
	# 石面鸟需要能被 lightflower 的光照释放打入 STUNNED。
	# STUNNED 中忽略重复触发；RESTING/WAKING/飞行态均可进入。
	if mode != Mode.STUNNED:
		_enter_light_stunned()



func _is_rest_area_available(area: Node, reserve_for_self: bool = false) -> bool:
	if area == null or not is_instance_valid(area):
		return false
	if area.has_method("can_accept_bird"):
		var ok := bool(area.call("can_accept_bird", self))
		if ok and reserve_for_self and area.has_method("reserve_for_bird"):
			return bool(area.call("reserve_for_bird", self))
		return ok
	return true


func has_available_rest_area() -> bool:
	var rest_areas := get_tree().get_nodes_in_group("rest_area")
	for area in rest_areas:
		if _is_rest_area_available(area, false):
			return true
	return false


func pick_available_rest_area() -> Node2D:
	var rest_areas := get_tree().get_nodes_in_group("rest_area")
	if rest_areas.is_empty():
		return null
	for area in rest_areas:
		if _is_rest_area_available(area, true):
			return area as Node2D
	return null


func occupy_rest_area(area: Node) -> void:
	if area == null or not is_instance_valid(area):
		return
	if area.has_method("occupy_by_bird") and not bool(area.call("occupy_by_bird", self)):
		return
	current_rest_area = area


func release_rest_area(area: Node = null) -> void:
	var target := area if area != null else current_rest_area
	if target != null and is_instance_valid(target) and target.has_method("release_by_bird"):
		target.call("release_by_bird", self)
	if area == null or target == current_rest_area:
		current_rest_area = null



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
			release_rest_area()
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

	# --- STUNNED / WAKE_FROM_STUN：允许扣血与闪白，但不切换 mode ---
	if mode == Mode.STUNNED or mode == Mode.WAKE_FROM_STUN:
		hp = max(hp - hit.damage, 0)
		hp = max(hp, 1)  # clamp 到 1，不会真死
		_flash_once()
		return true

	# --- FLYING_ATTACK / HURT：正常受击处理 ---
	hp = max(hp - hit.damage, 0)
	_flash_once()

	# HP<=1：进入 weak + STUNNED（包含 hp<=0 的情况，防止直接死亡消失）
	if hp <= weak_hp:
		_enter_weak_stunned()
		return true

	# 雷花 / 治愈精灵爆炸：强制进入 weak + STUNNED
	if hit.weapon_id == &"lightning_flower" or hit.weapon_id == &"healing_burst":
		_enter_weak_stunned()
		return true

	# 普通飞行受击 → HURT（0.2s 击退 + 闪白）
	if mode == Mode.FLYING_ATTACK:
		mode = Mode.HURT
	return true


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
	# 飞行状态：造成 1 点伤害（走本怪自定义规则，避免 EntityBase 直杀）
	if hp_locked:
		_flash_once()
		return 0
	hp = max(hp - 1, 0)
	_flash_once()
	if hp <= weak_hp:
		_enter_weak_stunned()
	elif mode == Mode.FLYING_ATTACK:
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
	if mode == Mode.FLYING_ATTACK or mode == Mode.HURT or mode == Mode.WAKING:
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
