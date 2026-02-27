extends Node2D
class_name GhostFist

## Ghost Fist 武器模块（V7 - 完全修复版 + ATTACK_HAND修正）
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

# ✅ CRITICAL FIX: 用户说 Attack 1 是 L 手主攻！
const ATTACK_HAND: Dictionary = {
	GFState.GF_ATTACK_1: Hand.LEFT,   # ✅ L先攻击
	GFState.GF_ATTACK_2: Hand.RIGHT,  # ✅ 连击时R攻击
	GFState.GF_ATTACK_3: Hand.RIGHT,
	GFState.GF_ATTACK_4: Hand.RIGHT,
}

# V7规范：L=-2/2, R=-1/3，玩家本体=0
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
@export var healing_sprite_scene: PackedScene

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
var _combo_check_handled: bool = false
var _combo_hit_count: int = 0
var _hit_this_swing: Dictionary = {}   # RID → true
var _last_hit_monster: Node2D = null   # 最近命中的怪物（摄魂用）
var _attack4_first_detected_monster: Node2D = null  # attack_4 首次检测到的怪物（摄魂VFX目标）
@export var idle_anima_delay: float = 5.0
var _idle_timer: float = 0.0

# ════════════════════════════════════════
# 外部依赖（setup 注入）
# ════════════════════════════════════════
var player: Node2D = null


func _gf_log(message: Variant, extra: Variant = null) -> void:
	if player == null or not is_instance_valid(player):
		return
	if not player.has_method("log_msg"):
		return
	var text: String = str(message)
	if extra != null:
		text += str(extra)
	player.call("log_msg", "GF", text)


func setup(p: Node2D) -> void:
	player = p
	_disable_all_hitboxes()
	visible = false  # 默认隐藏，activate 时显示
	
	# 连接 Hitbox 信号
	if _hitbox_L != null:
		_hitbox_L.area_entered.connect(_on_hitbox_area_entered)
	else:
		push_error("[GF_SETUP] HitboxL is null!")
	
	if _hitbox_R != null:
		_hitbox_R.area_entered.connect(_on_hitbox_area_entered)
	else:
		push_error("[GF_SETUP] HitboxR is null!")
	
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
	_gf_L.z_index = GF_Z_FRONT_L  # 2
	_gf_R.z_index = GF_Z_FRONT_R  # 3
	# ——后续不变——
	_combo_hit_count = 0
	queued_next = false
	hit_confirmed = false
	_combo_check_handled = false
	_hit_this_swing.clear()
	_last_hit_monster = null
	_attack4_first_detected_monster = null
	state = GFState.GF_ENTER
	
	# 切换到 GhostFist 时不附赠初始能量，必须依靠外部事件充能
	visible_time = 0.0
	light_counter = 0.0
	_materialized = false
	_update_opacity()
	
	_gf_log("[GF] ═══════════════════════════════════════")
	_gf_log("[GF] ACTIVATED")
	_gf_log("[GF] z_L=%d z_R=%d" % [_gf_L.z_index, _gf_R.z_index])
	_gf_log("[GF] materialized=%s visible_time=%s" % [_materialized, visible_time])
	_gf_log("[GF] ═══════════════════════════════════════")
	# PlayerAnimator 负责播放 enter 动画（三节点）


func deactivate() -> void:
	_disable_all_hitboxes()
	queued_next = false
	hit_confirmed = false
	_combo_check_handled = false
	state = GFState.GF_EXIT
	_gf_log("[GF] DEACTIVATED -> GF_EXIT")


# ════════════════════════════════════════
# 输入
# ════════════════════════════════════════
func on_attack_input() -> void:
	_gf_log("[GF] on_attack_input: state=%s" % GFState.keys()[state])
	match state:
		GFState.GF_IDLE:
			_start_attack(1)
		GFState.GF_ATTACK_1, GFState.GF_ATTACK_2, GFState.GF_ATTACK_3:
			queued_next = true
			_gf_log("[GF]   → queued_next = true")
		_:
			_gf_log("[GF]   → IGNORED (state=%s)" % GFState.keys()[state])


# ════════════════════════════════════════
# 攻击段
# ════════════════════════════════════════
func _start_attack(stage: int) -> void:
	state = GFState.GF_ATTACK_1 + (stage - 1)
	queued_next = false
	hit_confirmed = false
	_combo_check_handled = false
	_hit_this_swing.clear()
	_attack4_first_detected_monster = null
	_disable_all_hitboxes()
	state_changed.emit(state, StringName("attack_%d" % stage))
	
	var expected_hand_str: String = "L" if ATTACK_HAND.get(state, -1) == Hand.LEFT else "R"
	_gf_log("[GF] ─────────────────────────────────────")
	_gf_log("[GF] START ATTACK %d" % stage)
	_gf_log("[GF] Expected hand: %s" % expected_hand_str)
	_gf_log("[GF] State: %s" % GFState.keys()[state])
	_gf_log("[GF] ─────────────────────────────────────")


# ════════════════════════════════════════
# Spine 事件回调（PlayerAnimator 转发，附带 hand 标识）
# ════════════════════════════════════════
func on_spine_event(hand: int, event_name: StringName) -> void:
	# ✅ CRITICAL: 必须依赖 hand 参数！
	# L/R skeleton 是独立的，事件从各自的 skeleton 发出
	
	var hand_str: String = "L" if hand == Hand.LEFT else "R"
	var expected_hand: int = ATTACK_HAND.get(state, -1)
	var expected_str: String = "L" if expected_hand == Hand.LEFT else "R"
	
	_gf_log("[GF] ┌─ SPINE EVENT ────────────────────────")
	_gf_log("[GF] │ Event: %s" % event_name)
	_gf_log("[GF] │ From hand: %s" % hand_str)
	_gf_log("[GF] │ State: %s" % GFState.keys()[state])
	_gf_log("[GF] │ Expected hand: %s" % expected_str)
	_gf_log("[GF] │ Materialized: %s" % _materialized)
	
	match event_name:
		&"hit_on":
			# 只有预期的主攻手才启用 hitbox
			if hand == expected_hand:
				_enable_hitbox_for(hand)
				_gf_log("[GF] │ → hit_on ACCEPTED for %s ✓" % hand_str)
			else:
				_gf_log("[GF] │ → hit_on IGNORED (expected %s) ✗" % expected_str)
		
		&"hit_off":
			if hand == expected_hand:
				_disable_hitbox_for(hand)
				_gf_log("[GF] │ → hit_off for %s" % hand_str)
			else:
				_gf_log("[GF] │ → hit_off IGNORED")
		
		&"combo_check":
			# combo_check 只响应主攻手的事件
			if hand == expected_hand:
				_gf_log("[GF] │ → combo_check ACCEPTED from %s ✓" % hand_str)
				_on_combo_check()
			else:
				_gf_log("[GF] │ → combo_check IGNORED (expected %s) ✗" % expected_str)
		
		&"z_front":
			# z 事件响应各自的手
			var old_z: int = _gf_L.z_index if hand == Hand.LEFT else _gf_R.z_index
			_set_z(hand, true)
			var new_z: int = _gf_L.z_index if hand == Hand.LEFT else _gf_R.z_index
			_gf_log("[GF] │ → z_front for %s: %d → %d ✓" % [hand_str, old_z, new_z])
		
		&"z_back":
			var old_z: int = _gf_L.z_index if hand == Hand.LEFT else _gf_R.z_index
			_set_z(hand, false)
			var new_z: int = _gf_L.z_index if hand == Hand.LEFT else _gf_R.z_index
			_gf_log("[GF] │ → z_back for %s: %d → %d ✓" % [hand_str, old_z, new_z])
		
		_:
			_gf_log("[GF] │ → Unknown event: %s" % event_name)
	
	_gf_log("[GF] └──────────────────────────────────────")


func on_animation_complete(_anim_name: StringName) -> void:
	_gf_log("[GF] Animation complete: %s (state=%s)" % [_anim_name, GFState.keys()[state]])
	match state:
		GFState.GF_ENTER:
			if _anim_name != &"" and _anim_name != &"ghost_fist_/enter":
				_gf_log("[GF] Enter completion ignored: anim=%s" % _anim_name)
				return
			state = GFState.GF_IDLE
			_gf_log("[GF]   → Enter complete, now IDLE")
		GFState.GF_COOLDOWN:
			if _anim_name != &"" and _anim_name != &"ghost_fist_/cooldown":
				_gf_log("[GF] Cooldown completion ignored: anim=%s" % _anim_name)
				return
			state = GFState.GF_IDLE
			_gf_log("[GF]   → Cooldown complete, now IDLE")
		GFState.GF_EXIT:
			if _anim_name != &"" and _anim_name != &"ghost_fist_/exit":
				_gf_log("[GF] Exit completion ignored: anim=%s" % _anim_name)
				return
			visible = false
			state = GFState.GF_IDLE
			state_changed.emit(state, &"exit_done")
			_gf_log("[GF]   → Exit complete, hidden")
		GFState.GF_ATTACK_1, GFState.GF_ATTACK_2, \
		GFState.GF_ATTACK_3, GFState.GF_ATTACK_4:
			if _combo_check_handled:
				_gf_log("[GF] Attack completion ignored (combo_check already handled)")
				return
			var stage: int = state - GFState.GF_ATTACK_1 + 1
			if stage < 3:
				_gf_log("[GF] ⚠ Attack %d ended without combo_check → fallback IDLE" % stage)
				state = GFState.GF_IDLE
				return
			_gf_log("[GF] ⚠ Attack %d ended without combo_check → fallback cooldown" % stage)
			_enter_cooldown()

# ════════════════════════════════════════
# 连击门控
# ════════════════════════════════════════
func _on_combo_check() -> void:
	_combo_check_handled = true
	_disable_all_hitboxes()
	var stage: int = state - GFState.GF_ATTACK_1 + 1  # 1..4
	
	_gf_log("[GF] ┌─ COMBO CHECK ────────────────────────")
	_gf_log("[GF] │ Stage: %d" % stage)
	_gf_log("[GF] │ Hit confirmed: %s" % hit_confirmed)
	_gf_log("[GF] │ Queued next: %s" % queued_next)
	_gf_log("[GF] │ Combo count: %d" % _combo_hit_count)

	if stage == 4:
		# 第四段：摄魂判定 + 直接进 cooldown
		if hit_confirmed and _combo_hit_count >= soul_capture_threshold:
			_gf_log("[GF] │ → Triggering soul capture!")
			_trigger_soul_capture()
		_gf_log("[GF] │ → Stage 4 complete, entering cooldown")
		_enter_cooldown()
		_gf_log("[GF] └──────────────────────────────────────")
		return

	# 1~3 段：命中 + 按键 → 续段
	if hit_confirmed and queued_next:
		_gf_log("[GF] │ → Combo continues to stage %d ✓" % (stage + 1))
		_gf_log("[GF] └──────────────────────────────────────")
		_start_attack(stage + 1)
		return

	# 遵循文档：stage < 3 直接回 IDLE（轻断连，不播 cooldown）
	if stage < 3:
		_gf_log("[GF] │ → Combo broken (stage=%d hit=%s queued=%s), back to IDLE ✗" % [stage, hit_confirmed, queued_next])
		_gf_log("[GF] └──────────────────────────────────────")
		state = GFState.GF_IDLE
		return

	_gf_log("[GF] │ → Combo broken (stage=%d hit=%s queued=%s), entering cooldown ✗" % [stage, hit_confirmed, queued_next])
	_gf_log("[GF] └──────────────────────────────────────")
	_enter_cooldown()


## Cooldown 状态说明：
## - 在连击断裂（miss 或未按键）时播放的"收招"过渡动画
## - 例如 attack_1 打空 → cooldown → idle
## - 或者 attack_3 连击失败 → cooldown → idle
## - 动画应表现为拳头从攻击姿态平滑回到待机姿态
## - 播放期间禁止攻击输入（防止连击系统被绕过）
## - cooldown 完成后自动回到 GF_IDLE 状态
func _enter_cooldown() -> void:
	state = GFState.GF_COOLDOWN
	state_changed.emit(state, &"cooldown")
	_gf_log("[GF] Entering cooldown")


func on_hurt() -> void:
	if state == GFState.GF_EXIT:
		return
	queued_next = false
	hit_confirmed = false
	_combo_check_handled = false
	_disable_all_hitboxes()
	state = GFState.GF_IDLE


func on_die() -> void:
	queued_next = false
	hit_confirmed = false
	_combo_check_handled = false
	_disable_all_hitboxes()
	state = GFState.GF_IDLE


func on_hurt_animation_finished() -> void:
	if state == GFState.GF_EXIT:
		return
	_enter_cooldown()


# ════════════════════════════════════════
# 摄魂
# ════════════════════════════════════════
func _trigger_soul_capture() -> void:
	var target_monster: Node2D = _attack4_first_detected_monster
	if target_monster == null or not is_instance_valid(target_monster):
		target_monster = _last_hit_monster
	if target_monster == null or not is_instance_valid(target_monster):
		return
	if soul_extract_vfx_scene == null:
		push_error("[GhostFist] soul_extract_vfx_scene not assigned!")
		return
	var vfx: Node2D = soul_extract_vfx_scene.instantiate() as Node2D
	target_monster.add_child(vfx)
	vfx.position = Vector2.ZERO
	_combo_hit_count = 0
	_gf_log("[GhostFist] SOUL CAPTURE → ", target_monster.name)
	_spawn_healing_sprite()


func _spawn_healing_sprite() -> void:
	if healing_sprite_scene == null:
		return
	if player == null or not is_instance_valid(player):
		return
	if player.has_method("get_healing_sprite_count"):
		var cur: int = int(player.call("get_healing_sprite_count"))
		if cur >= player.max_healing_sprites:
			_gf_log("[GF] Healing sprite NOT spawned: player at max (%d)" % player.max_healing_sprites)
			return

	var sprite: Node2D = healing_sprite_scene.instantiate() as Node2D
	if sprite == null:
		return

	var parent: Node = player.get_parent()
	if parent == null:
		parent = player
	parent.add_child(sprite)
	sprite.global_position = player.global_position + Vector2(randf_range(-30.0, 30.0), -80.0)


# ════════════════════════════════════════
# 命中处理
# ════════════════════════════════════════
func _on_hitbox_area_entered(area: Area2D) -> void:
	if area == null:
		return
	if not _materialized:
		return

	var rid: RID = area.get_rid()
	if _hit_this_swing.has(rid):
		return

	var monster: Node = _resolve_monster(area)
	if monster != null:
		var monster_2d: Node2D = monster as Node2D
		if state == GFState.GF_ATTACK_4 and monster_2d != null and (_attack4_first_detected_monster == null or not is_instance_valid(_attack4_first_detected_monster)):
			_attack4_first_detected_monster = monster_2d
			_gf_log("[GF] attack_4 first detected target=%s" % monster_2d.name)
		var hit: HitData = HitData.create(damage_per_hit, player, &"ghost_fist", HitData.Flags.STAGGER)
		var applied: bool = monster.apply_hit(hit)
		_hit_this_swing[rid] = true
		if applied:
			hit_confirmed = true
			_combo_hit_count += 1
			_last_hit_monster = monster_2d
		return

	var flower = _resolve_lightning_flower(area)
	if flower != null:
		_hit_this_swing[rid] = true
		flower.on_chain_hit(player, 0)
		return

	var breakable: Node = _resolve_breakable(area)
	if breakable != null and breakable.has_method("apply_hit"):
		var hit_breakable: HitData = HitData.create(damage_per_hit, player, &"ghost_fist", HitData.Flags.STAGGER)
		if bool(breakable.call("apply_hit", hit_breakable)):
			_hit_this_swing[rid] = true
			hit_confirmed = true
			_combo_hit_count += 1
		return


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
		_gf_log("[GF] │   ➤ Enable hitbox %s (global_pos=%s)" % [
			"L" if hand == Hand.LEFT else "R",
			hb.global_position
		])


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
	_sync_hitbox_to_bone(_hitbox_L, _gf_L, "L")
	_sync_hitbox_to_bone(_hitbox_R, _gf_R, "R")


func _sync_hitbox_to_bone(hb: Area2D, spine: SpineSprite, hand_name: String) -> void:
	if hb == null or spine == null:
		return
	
	# 优先: get_global_bone_transform（直接返回全局坐标）
	if spine.has_method("get_global_bone_transform"):
		var t: Transform2D = spine.get_global_bone_transform("fist_core")
		hb.global_position = t.origin
		if Engine.get_physics_frames() % 60 == 0 and hb.monitoring:
			_gf_log("[GF_HITBOX] %s: global_pos=%s monitoring=%s" % [
				hand_name, hb.global_position, hb.monitoring
			])
		return
	
	# Fallback: 手动骨骼坐标 → to_global
	var skeleton = spine.get_skeleton()
	if skeleton == null:
		if Engine.get_physics_frames() % 120 == 0:
			push_error("[GF_HITBOX] %s: skeleton is null!" % hand_name)
		return
	
	var bone = skeleton.find_bone("fist_core")
	if bone == null:
		if Engine.get_physics_frames() % 120 == 0:
			push_error("[GF_HITBOX] %s: fist_core bone not found!" % hand_name)
		return
	
	# ✅ FIX: Spine和Godot Y轴方向一致，不需要取反！
	var bone_local: Vector2 = Vector2(bone.get_world_x(), bone.get_world_y())
	hb.global_position = spine.to_global(bone_local)
	
	if Engine.get_physics_frames() % 60 == 0 and hb.monitoring:
		_gf_log("[GF_HITBOX] %s: bone_local=%s global_pos=%s monitoring=%s" % [
			hand_name, bone_local, hb.global_position, hb.monitoring
		])


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




func _resolve_breakable(area_or_body: Node) -> Node:
	var cur: Node = area_or_body
	if cur != null and cur.has_method("get_host"):
		var host: Node = cur.call("get_host") as Node
		if host != null:
			cur = host
	for _i: int in range(6):
		if cur == null:
			return null
		if cur is MonsterBase or cur is LightningFlower:
			return null
		if cur.has_method("apply_hit"):
			return cur
		cur = cur.get_parent()
	return null

func _resolve_lightning_flower(area_or_body: Node) -> LightningFlower:
	var cur: Node = area_or_body
	for _i: int in range(4):
		if cur == null:
			return null
		if cur is LightningFlower:
			return cur as LightningFlower
		cur = cur.get_parent()
	return null


func get_current_stage() -> int:
	if state >= GFState.GF_ATTACK_1 and state <= GFState.GF_ATTACK_4:
		return state - GFState.GF_ATTACK_1 + 1
	return 0


func is_in_attack() -> bool:
	return state >= GFState.GF_ATTACK_1 and state <= GFState.GF_ATTACK_4


func is_active() -> bool:
	return visible


# ════════════════════════════════════════
# 能量 / 可见性系统
# ════════════════════════════════════════

func _physics_process(delta: float) -> void:
	_thunder_processed_this_frame = false
	if not visible:
		return
	_update_visibility(delta)
	# ✅ CRITICAL: 每帧更新 Hitbox 位置
	update_hitbox_positions()

	if state == GFState.GF_IDLE:
		_idle_timer += delta
		if _idle_timer >= idle_anima_delay:
			_idle_timer = 0.0
			state_changed.emit(state, &"idle_anima")
	else:
		_idle_timer = 0.0


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
			_gf_log("[GF] Materialized: visible_time=%s" % visible_time)
		_update_opacity()
		visible_time -= dt
		visible_time = max(visible_time, 0.0)
	else:
		if _materialized:
			_materialized = false
			_gf_log("[GF] Dematerialized")
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


func _get_current_light_remaining(info: Dictionary) -> float:
	var total_duration: float = info.get("total_duration", 0.0)
	if total_duration <= 0.0:
		return 0.0
	var start_ms: int = int(info.get("start_time_ms", 0))
	var elapsed: float = maxf((Time.get_ticks_msec() - start_ms) / 1000.0, 0.0)
	return maxf(total_duration - elapsed, 0.0)


func _on_light_started(source_id: int, remaining_time: float, source_light_area: Area2D) -> void:
	if _light_sensor == null or source_light_area == null:
		return
	if not source_light_area.overlaps_area(_light_sensor):
		_active_light_sources[source_id] = {
			"area": source_light_area,
			"total_duration": remaining_time,
			"start_time_ms": Time.get_ticks_msec(),
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
				var remaining: float = _get_current_light_remaining(info)
				light_counter += remaining
				light_counter = min(light_counter, light_counter_max)
			_active_light_sources.erase(src_id)
			break
