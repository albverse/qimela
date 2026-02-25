extends Node2D
class_name GhostFist

## Ghost Fist 武器模块（V7）
## 自封装场景：2 SpineSprite（L/R）+ z_index 切换 + 6 状态 FSM
## 路径: res://scene/weapons/ghost_fist/ghost_fist.gd

# ════════════════════════════════════════
# 枚举与常量
# ════════════════════════════════════════
enum GFState {
	GF_ENTER,     # 切到 GhostFist 时的出场动画（禁攻）
	GF_IDLE,      # 可攻击、待机悬浮
	GF_ATTACK_1,  # 第一段攻击
	GF_ATTACK_2,  # 第二段攻击
	GF_ATTACK_3,  # 第三段攻击
	GF_ATTACK_4,  # 第四段攻击
	GF_COOLDOWN,  # 收招冷却（禁攻）
	GF_EXIT,      # 退场（禁攻）
}

enum Hand { LEFT, RIGHT }

const ATTACK_HAND: Dictionary = {
	GFState.GF_ATTACK_1: Hand.RIGHT,
	GFState.GF_ATTACK_2: Hand.LEFT,
	GFState.GF_ATTACK_3: Hand.RIGHT,
	GFState.GF_ATTACK_4: Hand.RIGHT,
}

const GF_Z_BACK_L: int = -2
const GF_Z_FRONT_L: int = 2
const GF_Z_BACK_R: int = -1
const GF_Z_FRONT_R: int = 3

# ════════════════════════════════════════
# 信号（通知 Animator 播放对应动画）
# ════════════════════════════════════════
signal state_changed(new_state: int, context: StringName)
## context: &"attack_N" / &"cooldown" / &"enter" / &"exit" / &"idle"

# ════════════════════════════════════════
# 参数
# ════════════════════════════════════════
@export var damage_per_hit: int = 1
@export var soul_capture_threshold: int = 4
@export var soul_extract_vfx_scene: PackedScene

# ════════════════════════════════════════
# 子节点引用
# ════════════════════════════════════════
@onready var _gf_L: SpineSprite = $ghost_fist_L
@onready var _gf_R: SpineSprite = $ghost_fist_R
@onready var _hitbox_L: Area2D = $HitboxL
@onready var _hitbox_R: Area2D = $HitboxR
@onready var _light_sensor: Area2D = $LightSensor

# ════════════════════════════════════════
# 能量可见性参数
# ════════════════════════════════════════
@export var light_counter_max: float = 10.0
@export var visible_time_max: float = 6.0
@export var opacity_full_threshold: float = 2.0  ## visible_time 达到此值时完全不透明
@export var energy_transfer_rate: float = 10.0   ## light_counter → visible_time 转换倍率

var light_counter: float = 0.0
var visible_time: float = 0.0
var _materialized: bool = false  ## 当前是否处于"实体化"状态
var _processed_light_sources: Dictionary = {}
var _active_light_sources: Dictionary = {}
var _thunder_processed_this_frame: bool = false

# ════════════════════════════════════════
# 状态
# ════════════════════════════════════════
var state: int = GFState.GF_IDLE
var queued_next: bool = false
var hit_confirmed: bool = false
var _combo_hit_count: int = 0
var _hit_this_swing: Dictionary = {}   # RID → true
var _last_hit_monster: Node2D = null   # 最近命中的怪物（摄魂用）

# ════════════════════════════════════════
# 外部依赖（setup 注入）
# ════════════════════════════════════════
var player: Node2D = null


func setup(p: Node2D) -> void:
	player = p
	_disable_all_hitboxes()
	visible = false  # 默认隐藏，activate 时显示
	# 连接 Hitbox 信号
	if _hitbox_L != null:
		_hitbox_L.area_entered.connect(_on_hitbox_area_entered)
	if _hitbox_R != null:
		_hitbox_R.area_entered.connect(_on_hitbox_area_entered)
	# 连接 EventBus 光照信号
	if EventBus != null:
		if EventBus.has_signal("thunder_burst"):
			EventBus.thunder_burst.connect(_on_thunder_burst)
		if EventBus.has_signal("healing_burst"):
			EventBus.healing_burst.connect(_on_healing_burst)
		if EventBus.has_signal("light_started"):
			EventBus.light_started.connect(_on_light_started)
		if EventBus.has_signal("light_finished"):
			EventBus.light_finished.connect(_on_light_finished)
	# LightSensor overlap
	if _light_sensor != null:
		_light_sensor.area_entered.connect(_on_light_area_entered)


# ════════════════════════════════════════
# 公开接口：SpineSprite 引用（供 PlayerAnimator 调用）
# ════════════════════════════════════════
func get_spine_L() -> SpineSprite:
	return _gf_L


func get_spine_R() -> SpineSprite:
	return _gf_R


# ════════════════════════════════════════
# 激活 / 停用
# ════════════════════════════════════════
func activate() -> void:
	visible = true
	# 默认: L 在玩家前方, R 在玩家后方（攻击时由 z_front/z_back 事件切换）
	_gf_L.z_index = GF_Z_FRONT_L
	_gf_R.z_index = GF_Z_BACK_R
	_combo_hit_count = 0
	queued_next = false
	hit_confirmed = false
	_hit_this_swing.clear()
	_last_hit_monster = null
	state = GFState.GF_ENTER
	# PlayerAnimator 负责播放 enter 动画（三节点）


func deactivate() -> void:
	visible = false
	_disable_all_hitboxes()
	state = GFState.GF_EXIT


# ════════════════════════════════════════
# 输入
# ════════════════════════════════════════
func on_attack_input() -> void:
	match state:
		GFState.GF_IDLE:
			_start_attack(1)
		GFState.GF_ATTACK_1, GFState.GF_ATTACK_2, GFState.GF_ATTACK_3:
			queued_next = true
		_:
			pass  # ENTER/EXIT/COOLDOWN/ATTACK_4 期间忽略


# ════════════════════════════════════════
# 攻击段
# ════════════════════════════════════════
func _start_attack(stage: int) -> void:
	state = GFState.GF_ATTACK_1 + (stage - 1)
	queued_next = false
	hit_confirmed = false
	_hit_this_swing.clear()
	_disable_all_hitboxes()
	state_changed.emit(state, StringName("attack_%d" % stage))


# ════════════════════════════════════════
# Spine 事件回调（PlayerAnimator 转发，附带 hand 标识）
# ════════════════════════════════════════
func on_spine_event(_hand: int, event_name: StringName) -> void:
	# 根据当前攻击段的 ATTACK_HAND 决定激活哪只手的 hitbox/z_index
	# 不依赖事件来源手（因为 L/R spine 共享动画，事件可能只在一方触发）
	var active_hand: int = ATTACK_HAND.get(state, -1)
	print("[GF] on_spine_event: %s  state=%d  active_hand=%d  materialized=%s" % [
		event_name, state, active_hand, str(_materialized)])
	match event_name:
		&"hit_on":
			if active_hand >= 0:
				_enable_hitbox_for(active_hand)
		&"hit_off":
			if active_hand >= 0:
				_disable_hitbox_for(active_hand)
		&"combo_check":
			_on_combo_check()
		&"z_front":
			if active_hand >= 0:
				_set_z(active_hand, true)
		&"z_back":
			if active_hand >= 0:
				_set_z(active_hand, false)


func on_animation_complete(_anim_name: StringName) -> void:
	match state:
		GFState.GF_ENTER:
			state = GFState.GF_IDLE
		GFState.GF_COOLDOWN:
			state = GFState.GF_IDLE
		GFState.GF_EXIT:
			pass  # WeaponController 处理后续
		GFState.GF_ATTACK_1, GFState.GF_ATTACK_2, \
		GFState.GF_ATTACK_3, GFState.GF_ATTACK_4:
			# 攻击动画播完但没有 combo_check 事件 → 进入 cooldown
			# （正常流程由 combo_check spine 事件驱动，这是安全网）
			_disable_all_hitboxes()
			_enter_cooldown()


# ════════════════════════════════════════
# 连击门控
# ════════════════════════════════════════
func _on_combo_check() -> void:
	_disable_all_hitboxes()
	var stage: int = state - GFState.GF_ATTACK_1 + 1  # 1..4

	if stage == 4:
		# 第四段：摄魂判定 + 直接进 cooldown
		if hit_confirmed and _combo_hit_count >= soul_capture_threshold:
			_trigger_soul_capture()
		_enter_cooldown()
		return

	# 1~3 段：命中 + 按键 → 续段
	if hit_confirmed and queued_next:
		_start_attack(stage + 1)
	else:
		_enter_cooldown()


func _enter_cooldown() -> void:
	state = GFState.GF_COOLDOWN
	state_changed.emit(state, &"cooldown")


# ════════════════════════════════════════
# 摄魂
# ════════════════════════════════════════
func _trigger_soul_capture() -> void:
	if _last_hit_monster == null or not is_instance_valid(_last_hit_monster):
		return
	if soul_extract_vfx_scene == null:
		push_error("[GhostFist] soul_extract_vfx_scene not assigned!")
		return
	var vfx: Node2D = soul_extract_vfx_scene.instantiate() as Node2D
	_last_hit_monster.add_child(vfx)
	vfx.position = Vector2.ZERO
	_combo_hit_count = 0
	print("[GhostFist] SOUL CAPTURE → ", _last_hit_monster.name)


# ════════════════════════════════════════
# 命中处理
# ════════════════════════════════════════
func _on_hitbox_area_entered(area: Area2D) -> void:
	if area == null:
		return
	# 未实体化时攻击不奏效
	if not _materialized:
		return
	var rid: RID = area.get_rid()
	if _hit_this_swing.has(rid):
		return
	var monster = _resolve_monster(area)
	if monster == null:
		return
	var hit: HitData = HitData.create(damage_per_hit, player, &"ghost_fist", HitData.Flags.STAGGER)
	var applied: bool = monster.apply_hit(hit)
	_hit_this_swing[rid] = true
	if applied:
		hit_confirmed = true
		_combo_hit_count += 1
		_last_hit_monster = monster


# ════════════════════════════════════════
# z_index 切换
# ════════════════════════════════════════
func _set_z(hand: int, front: bool) -> void:
	if hand == Hand.LEFT:
		_gf_L.z_index = GF_Z_FRONT_L if front else GF_Z_BACK_L
	else:
		_gf_R.z_index = GF_Z_FRONT_R if front else GF_Z_BACK_R


# ════════════════════════════════════════
# Hitbox 管理
# ════════════════════════════════════════
func _enable_hitbox_for(hand: int) -> void:
	var hb: Area2D = _hitbox_L if hand == Hand.LEFT else _hitbox_R
	if hb != null:
		hb.set_deferred("monitoring", true)


func _disable_hitbox_for(hand: int) -> void:
	var hb: Area2D = _hitbox_L if hand == Hand.LEFT else _hitbox_R
	if hb != null:
		hb.set_deferred("monitoring", false)


func _disable_all_hitboxes() -> void:
	_disable_hitbox_for(Hand.LEFT)
	_disable_hitbox_for(Hand.RIGHT)


# ════════════════════════════════════════
# Hitbox 骨骼跟随
# ════════════════════════════════════════
func update_hitbox_positions() -> void:
	_sync_hitbox_to_bone(_hitbox_L, _gf_L)
	_sync_hitbox_to_bone(_hitbox_R, _gf_R)


func _sync_hitbox_to_bone(hb: Area2D, spine: SpineSprite) -> void:
	if hb == null or spine == null:
		return
	# 优先: get_global_bone_transform（直接返回全局坐标）
	if spine.has_method("get_global_bone_transform"):
		var t: Transform2D = spine.get_global_bone_transform("fist_core")
		hb.global_position = t.origin
		return
	# Fallback: 手动骨骼坐标 → to_global
	var skeleton = spine.get_skeleton()
	if skeleton == null:
		return
	var bone = skeleton.find_bone("fist_core")
	if bone == null:
		return
	var bone_local: Vector2 = Vector2(bone.get_world_x(), -bone.get_world_y())
	hb.global_position = spine.to_global(bone_local)


# ════════════════════════════════════════
# 工具
# ════════════════════════════════════════
func _resolve_monster(area_or_body: Node) -> Node:
	var cur: Node = area_or_body
	if cur.has_method("get_host"):
		cur = cur.call("get_host")
	for _i: int in range(6):
		if cur == null:
			return null
		if cur is MonsterBase:
			return cur
		cur = cur.get_parent()
	return null


func get_current_stage() -> int:
	if state >= GFState.GF_ATTACK_1 and state <= GFState.GF_ATTACK_4:
		return state - GFState.GF_ATTACK_1 + 1
	return 0


func is_in_attack() -> bool:
	return state >= GFState.GF_ATTACK_1 and state <= GFState.GF_ATTACK_4


func is_active() -> bool:
	return visible and state != GFState.GF_EXIT


# ════════════════════════════════════════
# 能量 / 可见性系统
# ════════════════════════════════════════

func _physics_process(delta: float) -> void:
	_thunder_processed_this_frame = false
	if not visible:
		return
	_update_visibility(delta)


func _update_visibility(dt: float) -> void:
	# 1) light_counter → visible_time（快速转换）
	if light_counter > 0.0:
		var transfer: float = min(light_counter, dt * energy_transfer_rate)
		visible_time += transfer
		light_counter -= transfer
		visible_time = min(visible_time, visible_time_max)

	# 2) visible_time 自然衰减（1 秒 / 秒）
	if visible_time > 0.0:
		if not _materialized:
			_materialized = true
		_update_opacity()
		visible_time -= dt
		visible_time = max(visible_time, 0.0)
	else:
		if _materialized:
			_materialized = false
			_update_opacity()


func _update_opacity() -> void:
	var alpha: float
	if visible_time >= opacity_full_threshold:
		alpha = 1.0
	elif visible_time > 0.0:
		alpha = clampf(visible_time / opacity_full_threshold, 0.0, 1.0)
	else:
		alpha = 0.0
	if _gf_L != null:
		_gf_L.modulate.a = alpha
	if _gf_R != null:
		_gf_R.modulate.a = alpha


# ── EventBus 信号处理 ──

func _on_thunder_burst(add_seconds: float) -> void:
	if _thunder_processed_this_frame:
		return
	_thunder_processed_this_frame = true
	light_counter += add_seconds
	light_counter = min(light_counter, light_counter_max)


func _on_healing_burst(light_energy: float) -> void:
	light_counter += light_energy
	light_counter = min(light_counter, light_counter_max)


func _on_light_started(source_id: int, remaining_time: float, source_light_area: Area2D) -> void:
	if _light_sensor == null or source_light_area == null:
		return
	if not source_light_area.overlaps_area(_light_sensor):
		_active_light_sources[source_id] = {
			"area": source_light_area,
			"remaining_time": remaining_time,
		}
		return
	if _processed_light_sources.has(source_id):
		return
	_processed_light_sources[source_id] = true
	light_counter += remaining_time
	light_counter = min(light_counter, light_counter_max)


func _on_light_finished(source_id: int) -> void:
	_processed_light_sources.erase(source_id)
	_active_light_sources.erase(source_id)


func _on_light_area_entered(area: Area2D) -> void:
	# LightSensor 进入了某个 light source 的 Area2D
	# 检查是否有对应的待处理 active_light_source
	for src_id: int in _active_light_sources.keys():
		var info: Dictionary = _active_light_sources[src_id]
		if info.get("area") == area:
			if not _processed_light_sources.has(src_id):
				_processed_light_sources[src_id] = true
				var remaining: float = info.get("remaining_time", 0.0)
				light_counter += remaining
				light_counter = min(light_counter, light_counter_max)
			_active_light_sources.erase(src_id)
			break
