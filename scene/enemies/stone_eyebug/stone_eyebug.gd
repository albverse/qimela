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

@export var soft_body_bone: String = "Mollusc"
## SoftHurtbox 追踪的 Spine 骨骼名；骨骼必须在 Spine 骨架中存在（蓝图规定命名：Mollusc）

@export var soft_body_fallback_offset: Vector2 = Vector2(0.0, 14.0)
## Mock 模式（无 Spine）或骨骼查询失败时 SoftHurtbox 的本地坐标偏移（px，相对根节点）

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

## 仅当玩家触发 retreat_in 后才允许攻击（并进入 2s 冷却窗口）
var attack_enabled_after_player_retreat: bool = false
var retreat_attack_lock_end_ms: int = 0

## FLIPPED 阶段是否已生成软体实例（防止重复 spawn）
var mollusc_spawned: bool = false

## 攻击命中检测窗口（供 ForceCloseHitWindows 安全机制使用，见 0.1 节）
var atk1_window_open: bool = false
var atk2_window_open: bool = false

## 本帧下一次 apply_hit() 视为软体命中（由 SoftHurtbox.get_host() 在命中前写入，命中后立即清除）
var _next_hit_is_soft: bool = false

# ===== Spine 事件标志（_on_spine_event 写入，BT 叶节点读取后立即清除）=====
## 攻击1命中窗口开/关（atk1_hit_on / atk1_hit_off）
var ev_atk1_hit_on: bool = false
var ev_atk1_hit_off: bool = false
## 攻击2命中窗口开/关（atk2_hit_on / atk2_hit_off）
var ev_atk2_hit_on: bool = false
var ev_atk2_hit_off: bool = false
## 缩壳动画完成（retreat_done）
var ev_retreat_done: bool = false
## 出壳动画完成（emerge_done）
var ev_emerge_done: bool = false
## 弹翻动画完成（flip_done）
var ev_flip_done: bool = false
## 软体生成精确帧（escape_spawn）
var ev_escape_spawn: bool = false

# ===== 动画状态追踪 =====

var _current_anim: StringName = &""
var _current_anim_finished: bool = false
var _current_anim_loop: bool = false

# ===== 动画驱动 =====

var _anim_driver: AnimDriverSpine = null
var _anim_mock: AnimDriverMock = null

var _shell_hurtbox: Area2D = null  ## 壳体受击盒缓存（Hurtbox 节点）
var _soft_hurtbox: Area2D = null   ## 软腹受击盒缓存（SoftHurtbox 节点）

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

	_shell_hurtbox = get_node_or_null("Hurtbox") as Area2D
	_soft_hurtbox = get_node_or_null("SoftHurtbox") as Area2D

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

	_update_hurtbox_states()
	# SoftHurtbox 位置追踪（Spine 骨骼或 Mock 偏移）
	# 注：AnimDriverSpine 是子节点，其 _physics_process 在本节点之后执行，存在 1 帧位置滞后，
	#     对游戏玩法判定无显著影响。
	_update_soft_hurtbox_position()

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


func _on_spine_event(_a1, _a2 = null, _a3 = null, _a4 = null) -> void:
	## Spine 动画事件回调（事件名解析后写入 ev_* 标志，BT 叶节点读取并驱动状态转移）
	var event_name: StringName = _extract_spine_event_name([_a1, _a2, _a3, _a4])
	if event_name == &"":
		return
	match event_name:
		&"atk1_hit_on":   ev_atk1_hit_on = true;  atk1_window_open = true
		&"atk1_hit_off":  ev_atk1_hit_off = true; atk1_window_open = false
		&"atk2_hit_on":   ev_atk2_hit_on = true;  atk2_window_open = true
		&"atk2_hit_off":  ev_atk2_hit_off = true; atk2_window_open = false
		&"retreat_done":  ev_retreat_done = true
		&"emerge_done":   ev_emerge_done = true
		&"flip_done":     ev_flip_done = true
		&"escape_spawn":  ev_escape_spawn = true


func _extract_spine_event_name(args: Array) -> StringName:
	## 从 Spine animation_event 信号的不定参数中提取事件名（兼容多版本 spine-godot 运行时）
	for arg in args:
		if arg == null:
			continue
		if arg is StringName:
			return arg
		if arg is String:
			return StringName(arg)
		# SpineTrackEntry.get_data() → SpineEventData.get_name()
		if arg.has_method("get_data"):
			var d: Variant = arg.get_data()
			if d != null:
				var n: StringName = _get_obj_name(d)
				if n != &"":
					return n
		var n: StringName = _get_obj_name(arg)
		if n != &"":
			return n
	return &""


func _get_obj_name(obj: Object) -> StringName:
	if obj.has_method("get_name"):
		return StringName(obj.get_name())
	if obj.has_method("getName"):
		return StringName(obj.getName())
	return &""


# =============================================================================
# 受击规则
# =============================================================================

func _is_player_attack(hit: HitData) -> bool:
	if hit == null:
		return false
	if hit.source != null and is_instance_valid(hit.source) and hit.source.is_in_group("player"):
		return true
	if hit.weapon_id == &"ghost_fist" or hit.weapon_id == &"chimera_ghost_hand_l":
		return true
	return false


func _can_flip_on_hit(hit: HitData) -> bool:
	if hit == null:
		return false
	if _is_player_attack(hit):
		return true
	if hit.weapon_id == &"stone_mask_bird_face_bullet":
		return true
	return false



func apply_hit(hit: HitData) -> bool:
	# 读取并立即清除软体命中标记（由 SoftHurtbox.get_host() 在本帧命中前写入）
	var is_soft_hit: bool = _next_hit_is_soft
	_next_hit_is_soft = false

	if hit == null:
		return false
	if not has_hp or hp <= 0:
		return false

	# 弹翻阶段：ShellHurtbox 已由 _update_hurtbox_states() 禁用，
	# 本阶段所有命中均来自 SoftHurtbox（soft_hitbox_active=true 时）
	if mode == Mode.FLIPPED:
		if soft_hitbox_active:
			# 软体易伤：标记 was_attacked_while_flipped → BT 触发分裂
			was_attacked_while_flipped = true
			_flash_once()
			return true
		return false

	# 空壳阶段：可被常规攻击打，走弱化流程
	if mode == Mode.EMPTY_SHELL:
		anim_play(&"hit_shell_small", false, false)  # 空壳受击视觉反馈
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

	# --- NORMAL 态软腹命中（通用攻击命中 SoftHurtbox）→ 缩壳，不扣血 ---
	if is_soft_hit and mode == Mode.NORMAL:
		mode = Mode.RETREATING
		shell_last_attacked_ms = Time.get_ticks_msec()
		if _is_player_attack(hit):
			attack_enabled_after_player_retreat = true
			retreat_attack_lock_end_ms = Time.get_ticks_msec() + int(attack_cd * 1000.0)
		_flash_once()
		return true

	# --- NORMAL 态可翻转命中（玩家武器 + 面具弹）---
	if mode == Mode.NORMAL and _can_flip_on_hit(hit):
		mode = Mode.FLIPPED
		_flash_once()
		return true

	# --- 其余武器命中壳体 → 反向行走 + 刷新受攻时间，伤害无效 ---
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
# 软体受击盒接口
# =============================================================================

func _mark_next_hit_soft() -> void:
	## 由 SoftHurtbox.get_host() 在命中前调用，标记本次 apply_hit() 为软体命中
	_next_hit_is_soft = true


func _update_hurtbox_states() -> void:
	## 按当前 mode 和 soft_hitbox_active 开关壳体 / 软腹受击盒的 monitoring
	## 每帧在 _physics_process 开头调用，保证与状态机同步
	if _shell_hurtbox == null and _soft_hurtbox == null:
		return
	match mode:
		Mode.NORMAL:
			# 壳体可被命中（反弹），软腹也可被命中（缩壳）
			if _shell_hurtbox:
				_shell_hurtbox.monitoring = true
			if _soft_hurtbox:
				_soft_hurtbox.monitoring = true
		Mode.RETREATING, Mode.IN_SHELL:
			# 缩壳 / 壳内：软腹已收起，只留壳体
			if _shell_hurtbox:
				_shell_hurtbox.monitoring = true
			if _soft_hurtbox:
				_soft_hurtbox.monitoring = false
		Mode.FLIPPED:
			# 翻倒：壳体朝下无法命中，软腹随 soft_hitbox_active 开关
			if _shell_hurtbox:
				_shell_hurtbox.monitoring = false
			if _soft_hurtbox:
				_soft_hurtbox.monitoring = soft_hitbox_active
		Mode.EMPTY_SHELL:
			# 空壳：只有壳可受击，软腹已逃走
			if _shell_hurtbox:
				_shell_hurtbox.monitoring = true
			if _soft_hurtbox:
				_soft_hurtbox.monitoring = false


func _update_soft_hurtbox_position() -> void:
	## 每帧将 SoftHurtbox 的 global_position 对齐到 Spine 骨骼（或 Mock 固定偏移）
	## AnimDriverSpine 是子节点，其 _physics_process 在本帧稍后执行，存在 1 帧骨骼滞后，
	## 对游戏命中判定无显著影响。
	if _soft_hurtbox == null:
		return
	if _anim_driver != null:
		var bone_pos: Vector2 = _anim_driver.get_bone_world_position(soft_body_bone)
		if bone_pos != Vector2.ZERO:
			_soft_hurtbox.global_position = bone_pos
			return
	# Fallback：无 Spine 或骨骼未找到，使用本地偏移
	_soft_hurtbox.position = soft_body_fallback_offset


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
	_anim_mock._durations[&"hit_shell_small"] = 0.25
