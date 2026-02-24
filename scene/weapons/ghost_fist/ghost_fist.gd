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
	_gf_L.z_index = GF_Z_BACK_L
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
func on_spine_event(hand: int, event_name: StringName) -> void:
	match event_name:
		&"hit_on":
			_enable_hitbox_for(hand)
		&"hit_off":
			_disable_hitbox_for(hand)
		&"combo_check":
			var expected: int = ATTACK_HAND.get(state, -1)
			if hand == expected:
				_on_combo_check()
		&"z_front":
			_set_z(hand, true)
		&"z_back":
			_set_z(hand, false)


func on_animation_complete(_anim_name: StringName) -> void:
	match state:
		GFState.GF_ENTER:
			state = GFState.GF_IDLE
		GFState.GF_COOLDOWN:
			state = GFState.GF_IDLE
		GFState.GF_EXIT:
			pass  # WeaponController 处理后续


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
	var skeleton = spine.get_skeleton()
	if skeleton == null:
		return
	var bone = skeleton.find_bone("fist_core")
	if bone == null:
		return
	var bone_pos: Vector2 = Vector2(bone.get_world_x(), -bone.get_world_y())
	hb.position = bone_pos  # 相对 GhostFist 节点的局部坐标


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
