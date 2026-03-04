extends MonsterBase
class_name StoneEyeBug

## =============================================================================
## StoneEyeBug - 石眼虫（Beehave x Spine 行为树怪物）
## =============================================================================
## 壳体阶段：巡走→缩壳→等待出壳循环。弹翻后软体逃跑。
## 行为由 Beehave 行为树驱动，动画由 AnimDriverSpine（或 AnimDriverMock fallback）驱动。
## =============================================================================

enum Mode {
	NORMAL = 0,      ## 正常状态：巡走 / 发呆 / 攻击
	RETREATING = 1,  ## 缩壳中（retreat_in 动画，0.5s）
	IN_SHELL = 2,    ## 壳内待机（in_shell_loop，5s 不受攻击才出壳）
	FLIPPED = 3,     ## 被弹翻（flip → struggle_loop，软体易伤）
	EMPTY_SHELL = 4, ## 软体逃跑后的空壳（等待软体回来，可被链接）
}

# ===== 导出参数（策划可调）=====

@export var idle_time: float = 4.0
## 发呆时长（秒）

@export var walk_speed: float = 60.0
## 行走速度（px/s）

@export var walk_style_min_hold: float = 1.2
## 走法动画最短保持时间（防抖，秒）

@export var attack_cd: float = 2.0
## 攻击冷却（秒）

@export var player_stone_stun: float = 2.0
## attack_stone 命中后玩家僵直时长（秒）

@export var retreat_time: float = 0.5
## 缩壳耗时（秒），与 retreat_in 动画同步

@export var shell_safe_time: float = 5.0
## 缩壳后未受攻击 5s 才出壳

@export var knockback_strength: float = 400.0
## attack_lick 击退强度（velocity px/s，严禁 position）

@export var detect_area_radius: float = 150.0
## 玩家检测区半径（px）—— 与场景内 DetectArea Shape 保持一致

@export var mollusc_scene: PackedScene = null
## 软体虫实例场景，运行时 spawn

# ===== 内部状态（BT 叶节点直接读写）=====

var mode: int = Mode.NORMAL

## 当前走法（0=walk_lick, 1=walk_backfloat, 2=walk_wriggle）
var walk_style: int = 0

## 走法保持截止时间（ms），防止同帧重选
var walk_style_hold_end_ms: int = 0

## 当前朝向（1=右, -1=左）
var facing: int = 1

## 是否是雷花触发的缩壳（先播 hit_shell 反应）
var is_thunder_pending: bool = false

## 软体伤害盒是否激活（弹翻阶段）
var soft_hitbox_active: bool = false

## 弹翻中是否被攻击（→ 触发分裂逃跑）
var was_attacked_while_flipped: bool = false

## 最后一次壳被攻击的时间戳（ms），用于 5s 出壳计时
var shell_last_attacked_ms: int = 0

## 攻击冷却截止时间戳（ms）
var next_attack_end_ms: int = 0

## FLIPPED 阶段是否已生成软体实例（防止重复 spawn）
var mollusc_spawned: bool = false

## 攻击命中检测窗口（供 ForceCloseHitWindows 安全机制使用，见 0.1 节）
var atk1_window_open: bool = false
var atk2_window_open: bool = false

# ===== 动画状态追踪 =====

var _current_anim: StringName = &""
var _current_anim_finished: bool = false
var _current_anim_loop: bool = false

# ===== 动画驱动 =====

var _anim_driver: AnimDriverSpine = null
var _anim_mock: AnimDriverMock = null

@onready var _spine_sprite: Node = null
@onready var _detect_area: Area2D = get_node_or_null("DetectArea")

# ===== 生命周期 =====

func _ready() -> void:
	species_id = &"stone_eyebug"
	attribute_type = AttributeType.DARK
	size_tier = SizeTier.SMALL
	max_hp = 5
	weak_hp = 1
	super._ready()
	add_to_group("stone_eyebug")

	_spine_sprite = get_node_or_null("SpineSprite")
	if _spine_sprite and _spine_sprite.get_class() == "SpineSprite":
		_anim_driver = AnimDriverSpine.new()
		add_child(_anim_driver)
		_anim_driver.setup(_spine_sprite)
		_anim_driver.anim_completed.connect(_on_anim_completed)
		if _spine_sprite.has_signal("animation_event"):
			_spine_sprite.animation_event.connect(_on_spine_event)
	else:
		_anim_mock = AnimDriverMock.new()
		_setup_mock_durations()
		add_child(_anim_mock)
		_anim_mock.anim_completed.connect(_on_anim_completed)


func _physics_process(dt: float) -> void:
	# 光照计数器
	if light_counter > 0.0:
		light_counter -= dt
		light_counter = max(light_counter, 0.0)
	_thunder_processed_this_frame = false

	# Mock 驱动需要手动 tick
	if _anim_mock:
		_anim_mock.tick(dt)

	# weak 倒计时
	if weak and weak_stun_t > 0.0:
		weak_stun_t = max(weak_stun_t - dt, 0.0)
		if weak_stun_t <= 0.0:
			_restore_from_weak()
			if mode == Mode.EMPTY_SHELL or mode == Mode.FLIPPED:
				mode = Mode.NORMAL

	# 移动和 BT 逻辑由叶节点（+ BeehaveTree tick）驱动，_physics_process 不再调用 super


func _do_move(_dt: float) -> void:
	pass  # 移动完全由 BT 叶节点控制


# =============================================================================
# 动画接口（BT 叶节点统一调用）
# =============================================================================

func anim_play(anim_name: StringName, loop: bool, _interruptible: bool = true) -> void:
	## 播放指定动画。叶节点只调这一个接口，不直接碰 Spine。
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


func anim_stop() -> void:
	_current_anim = &""
	_current_anim_finished = true
	if _anim_driver:
		_anim_driver.stop_all()
	elif _anim_mock:
		_anim_mock.stop(0)


func _on_anim_completed(_track: int, anim_name: StringName) -> void:
	if anim_name == _current_anim:
		_current_anim_finished = true


func _on_spine_event(_a1, _a2, _a3, _a4) -> void:
	## Spine 事件回调（escape_spawn 等事件由 BT 动作轮询计时，不依赖此信号）
	pass


# =============================================================================
# 受击规则
# =============================================================================

func apply_hit(hit: HitData) -> bool:
	if hit == null:
		return false
	if not has_hp or hp <= 0:
		return false

	# 弹翻阶段
	if mode == Mode.FLIPPED:
		if soft_hitbox_active:
			# 软体易伤：标记 was_attacked_while_flipped → BT 触发分裂
			was_attacked_while_flipped = true
			_flash_once()
			return true
		return false

	# 空壳阶段：可被常规攻击打，走弱化流程
	if mode == Mode.EMPTY_SHELL:
		if hp_locked:
			_flash_once()
			return true
		hp = max(hp - hit.damage, 0)
		_flash_once()
		_update_weak_state()
		if hp <= 0 and not hp_locked:
			_on_death()
		return true

	# 壳体保护阶段（NORMAL / RETREATING / IN_SHELL）
	# --- 雷花 → 触发缩壳 ---
	if hit.weapon_id == &"lightning_flower" or hit.weapon_id == &"lightflower":
		if mode != Mode.RETREATING and mode != Mode.IN_SHELL:
			is_thunder_pending = true
			mode = Mode.RETREATING
		else:
			# 已在壳内：刷新受攻时间，壳继续保护
			shell_last_attacked_ms = Time.get_ticks_msec()
		_flash_once()
		return true

	# --- ghost_fist / chimera_ghost_hand_l → 弹翻（仅 NORMAL 态壳外）---
	if hit.weapon_id == &"ghost_fist" or hit.weapon_id == &"chimera_ghost_hand_l":
		if mode == Mode.NORMAL:
			mode = Mode.FLIPPED
			_flash_once()
			return true
		# 缩壳/壳内：壳保护，反向行走，刷新受攻时间
		_reflect_from_shell(hit)
		return true

	# --- StoneMaskBirdFaceBullet → 弹翻（仅 NORMAL 态）---
	if hit.weapon_id == &"stone_mask_bird_face_bullet":
		if mode == Mode.NORMAL:
			mode = Mode.FLIPPED
			_flash_once()
			return true
		_reflect_from_shell(hit)
		return true

	# --- 软体命中（弹翻前，NORMAL 且未弹翻）→ 缩壳 ---
	# 注：在弹翻前，软体骨骼被打到 → 触发缩壳（不扣血，只闪白）
	# weapon_id 留空或使用通用攻击：在 NORMAL 态软体被命中逻辑
	# 其他武器命中壳体 → 反向行走 + 刷新受攻时间，伤害无效

	_reflect_from_shell(hit)
	return true


func _reflect_from_shell(hit: HitData) -> void:
	## 壳体被命中：反向行走，刷新受攻计时
	shell_last_attacked_ms = Time.get_ticks_msec()
	if hit.source != null and is_instance_valid(hit.source):
		var dx: float = hit.source.global_position.x - global_position.x
		if dx > 0.0:
			facing = -1
		elif dx < 0.0:
			facing = 1
	_flash_once()


# =============================================================================
# 锁链交互
# =============================================================================

func on_chain_hit(_player: Node, _slot: int) -> int:
	# 空壳 + 虚弱 → 可链接
	if mode == Mode.EMPTY_SHELL and weak:
		_linked_player = _player
		return 1
	# 其他状态：链碰壳体直接消失（返回 0，伤害不生效）
	return 0


# =============================================================================
# 状态切换辅助（供 BT 叶节点调用）
# =============================================================================

func force_close_hit_windows() -> void:
	## 强制关闭所有命中检测窗口（见 0.1 节：强制打断必须强制关命中窗口）
	atk1_window_open = false
	atk2_window_open = false


func notify_become_empty_shell() -> void:
	## 软体逃跑后，将壳变为空壳状态
	mode = Mode.EMPTY_SHELL
	species_id = &"stone_eyebug_shell"
	soft_hitbox_active = false
	mollusc_spawned = true
	# 空壳重置 HP，进入可被弱化流程
	hp = max_hp
	weak = false
	hp_locked = false
	vanish_fusion_count = 0


func notify_shell_restored() -> void:
	## 软体归来：壳恢复为缩壳待机状态
	mode = Mode.IN_SHELL
	species_id = &"stone_eyebug"
	mollusc_spawned = false
	shell_last_attacked_ms = Time.get_ticks_msec()


func spawn_mollusc_instance() -> Node2D:
	## 在 escape_spawn 帧生成软体实例
	if mollusc_scene == null:
		push_error("[StoneEyeBug] mollusc_scene 未设置，无法生成软体虫")
		return null
	var m: Node = (mollusc_scene as PackedScene).instantiate()
	var m2d := m as Node2D
	if m2d != null:
		m2d.global_position = global_position
	get_parent().add_child(m)
	if m.has_method("set_home_shell"):
		m.call("set_home_shell", self)
	return m2d


func is_player_in_detect_area() -> bool:
	## 自给自足地检测玩家是否在检测范围内
	if _detect_area == null:
		var players := get_tree().get_nodes_in_group("player")
		if players.is_empty():
			return false
		var p := players[0] as Node2D
		if p == null:
			return false
		return global_position.distance_to(p.global_position) <= detect_area_radius
	return _detect_area.has_overlapping_bodies() or _detect_area.has_overlapping_areas()


func get_player() -> Node2D:
	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return null
	return players[0] as Node2D


static func now_ms() -> int:
	return Time.get_ticks_msec()


# =============================================================================
# Mock 驱动时长
# =============================================================================

func _setup_mock_durations() -> void:
	_anim_mock._durations[&"idle"] = 1.0
	_anim_mock._durations[&"walk_lick"] = 0.8
	_anim_mock._durations[&"walk_backfloat"] = 0.8
	_anim_mock._durations[&"walk_wriggle"] = 0.8
	_anim_mock._durations[&"hit_shell"] = 0.3
	_anim_mock._durations[&"retreat_in"] = 0.5
	_anim_mock._durations[&"in_shell_loop"] = 1.0
	_anim_mock._durations[&"emerge_out"] = 0.5
	_anim_mock._durations[&"attack_stone"] = 0.6
	_anim_mock._durations[&"attack_lick"] = 0.5
	_anim_mock._durations[&"flip"] = 0.4
	_anim_mock._durations[&"struggle_loop"] = 1.0
	_anim_mock._durations[&"escape_split"] = 0.6
