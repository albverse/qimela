extends MonsterBase
class_name WanderingGhost

# =============================================================================
# WanderingGhost - 游荡幽灵
# 飞行型幽灵怪物，无HP，只能被 ghost_fist / chimera_ghost_hand_l 一击杀死。
# 拥有显隐系统（复用 MonsterFly 模式），隐身时仍追击玩家但不攻击。
# =============================================================================

# ===== 移动参数 =====
@export var move_speed: float = 80.0  # 追击移动速度(像素/秒)
@export var chase_delay: float = 1.0  # 首次检测到玩家后的延迟(秒)
@export var attack_cooldown: float = 0.8  # 攻击冷却(秒)

# ===== 可见性系统 =====
@export var visible_time: float = 0.0  # 当前可见时间(秒)
@export var visible_time_max: float = 6.0  # 最大可见时间(秒)
@export var opacity_full_threshold: float = 3.0  # 完全不透明阈值(秒)
@export var fade_curve: Curve = null  # 淡入淡出曲线

@export var light_node_path: NodePath = ^"PointLight2D"
@onready var _point_light: PointLight2D = get_node_or_null(light_node_path) as PointLight2D

# ===== 运行时状态 =====
var _dying: bool = false
var _being_hunted: bool = false
var _is_visible: bool = false
var _saved_body_layer: int = -1
var _attack_cd_t: float = 0.0
var _has_started_chase_once: bool = false

# ===== Spine =====
var _spine: Node = null
var _current_anim: StringName = &""

# ===== 攻击动画轮询兜底 =====
var _attack_anim_playing: bool = false


func _ready() -> void:
	# ===== 物种设置 =====
	species_id = &"wandering_ghost"
	attribute_type = AttributeType.LIGHT
	size_tier = SizeTier.SMALL
	has_hp = false  # 无HP系统，一击死亡

	# ===== 组 =====
	add_to_group("ghost")  # chain 自动穿透语义
	add_to_group("huntable_ghost")  # 允许被噬魂犬捕食

	# ===== LightReceiver 显式绑定（FIX-V4-01）=====
	light_receiver_path = NodePath("LightReceiver")

	# 保存碰撞层（显隐切换用）
	_saved_body_layer = collision_layer

	super._ready()

	# ===== Spine 初始化 =====
	_spine = get_node_or_null("SpineSprite")
	if _spine != null:
		if _spine.has_signal("animation_completed"):
			_spine.animation_completed.connect(_on_anim_completed_raw)
		if _spine.has_signal("animation_event"):
			_spine.animation_event.connect(_on_spine_event)

	# ===== 初始状态：隐身 =====
	if visible_time <= 0.0:
		_switch_to_invisible()
	else:
		_switch_to_visible()


func _physics_process(dt: float) -> void:
	if _dying or _being_hunted:
		return

	_update_visibility(dt)

	# 攻击冷却递减
	if _attack_cd_t > 0.0:
		_attack_cd_t -= dt
		if _attack_cd_t < 0.0:
			_attack_cd_t = 0.0

	super._physics_process(dt)


# =============================================================================
# 显隐系统（复用 MonsterFly 逻辑，行为不同）
# =============================================================================
func _update_visibility(dt: float) -> void:
	# light_counter → visible_time 转换（速率 dt * 10.0）
	if light_counter > 0.0:
		var transfer: float = min(light_counter, dt * 10.0)
		visible_time += transfer
		light_counter -= transfer
		visible_time = min(visible_time, visible_time_max)

	if visible_time > 0.0:
		if not _is_visible:
			_switch_to_visible()
		_update_opacity()
		visible_time -= dt
		visible_time = max(visible_time, 0.0)
	else:
		if _is_visible:
			_switch_to_invisible()


func _update_opacity() -> void:
	if sprite == null:
		return
	var alpha: float
	if visible_time >= opacity_full_threshold:
		alpha = 1.0
	else:
		var t: float = visible_time / opacity_full_threshold
		if fade_curve != null:
			alpha = fade_curve.sample(t)
		else:
			alpha = lerpf(0.0, 1.0, t)
	sprite.modulate.a = alpha
	if _point_light:
		_point_light.energy = alpha * 1.0


func _switch_to_visible() -> void:
	_is_visible = true
	if _saved_body_layer != -1:
		collision_layer = _saved_body_layer
	if sprite:
		sprite.visible = true
		sprite.modulate.a = 1.0
	var hurtbox: Area2D = get_node_or_null("Hurtbox") as Area2D
	if hurtbox:
		hurtbox.set_deferred("monitorable", true)
		hurtbox.set_deferred("monitoring", true)
		var hurtbox_shape: CollisionShape2D = hurtbox.get_node_or_null("CollisionShape2D") as CollisionShape2D
		if hurtbox_shape:
			hurtbox_shape.disabled = false
	var attack_area: Area2D = get_node_or_null("AttackArea") as Area2D
	if attack_area:
		attack_area.monitoring = true
	if _point_light:
		_point_light.enabled = true


func _switch_to_invisible() -> void:
	_is_visible = false
	collision_layer = 0
	# collision_mask 保持不变（防止穿模）
	if sprite:
		sprite.visible = false
		sprite.modulate.a = 0.0
	var hurtbox: Area2D = get_node_or_null("Hurtbox") as Area2D
	if hurtbox:
		hurtbox.set_deferred("monitorable", false)
		hurtbox.set_deferred("monitoring", false)
		var hurtbox_shape: CollisionShape2D = hurtbox.get_node_or_null("CollisionShape2D") as CollisionShape2D
		if hurtbox_shape:
			hurtbox_shape.disabled = true
	var attack_area: Area2D = get_node_or_null("AttackArea") as Area2D
	if attack_area:
		attack_area.monitoring = false
	# 立即关闭 AttackHitbox（攻击过程中切入隐身）
	set_attack_hitbox_active(false)
	if _point_light:
		_point_light.enabled = false


# =============================================================================
# 受击与死亡
# =============================================================================
func apply_hit(hit: HitData) -> bool:
	if _dying or _being_hunted:
		return false
	if hit == null:
		return false
	if hit.weapon_id != &"ghost_fist" and hit.weapon_id != &"chimera_ghost_hand_l":
		return false
	_dying = true
	_play_anim(&"death", false)
	return true


func on_chain_hit(_p: Node, _s: int) -> int:
	return 0  # 链条直接穿过


# =============================================================================
# 被吞食（噬魂狗猎杀）
# =============================================================================
func is_being_hunted() -> bool:
	return _being_hunted


func is_dying() -> bool:
	return _dying


func is_ghost_visible() -> bool:
	return _is_visible


func start_being_hunted() -> void:
	_being_hunted = true
	velocity = Vector2.ZERO
	# 立即关闭所有碰撞/检测/行为
	var attack_area: Area2D = get_node_or_null("AttackArea") as Area2D
	if attack_area:
		attack_area.monitoring = false
	var attack_hitbox: Area2D = get_node_or_null("AttackHitbox") as Area2D
	if attack_hitbox:
		attack_hitbox.monitoring = false
		attack_hitbox.monitorable = false
	var detect_area: Area2D = get_node_or_null("DetectArea") as Area2D
	if detect_area:
		detect_area.monitoring = false
	var hurtbox: Area2D = get_node_or_null("Hurtbox") as Area2D
	if hurtbox:
		hurtbox.monitoring = false
		hurtbox.monitorable = false
	_play_anim(&"hunted", false)


# =============================================================================
# AttackHitbox 控制（由 Spine 事件驱动）
# =============================================================================
func set_attack_hitbox_active(active: bool) -> void:
	var hitbox: Area2D = get_node_or_null("AttackHitbox") as Area2D
	if hitbox == null:
		return
	if active and not _is_visible:
		# 隐身时不允许开启 hitbox
		active = false
	hitbox.monitoring = active
	hitbox.monitorable = active
	var shape: CollisionShape2D = hitbox.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape:
		shape.disabled = not active

func _on_attack_hitbox_body_entered(body: Node2D) -> void:
	if _dying or _being_hunted:
		return
	if not _is_visible:
		return
	if body.has_method("apply_damage"):
		body.call("apply_damage", 1, global_position)
# =============================================================================
# Spine 动画
# =============================================================================
func _play_anim(anim_name: StringName, loop: bool) -> void:
	if _spine == null:
		return
	if _current_anim == anim_name:
		return
	_current_anim = anim_name
	var anim_state: Object = null
	if _spine.has_method("get_animation_state"):
		anim_state = _spine.get_animation_state()
	elif _spine.has_method("getAnimationState"):
		anim_state = _spine.getAnimationState()
	if anim_state == null:
		return
	# 直接 set_animation 替换，禁止先 clear_track（SPINE §2.4）
	if anim_state.has_method("set_animation"):
		anim_state.set_animation(String(anim_name), loop, 0)
	elif anim_state.has_method("setAnimation"):
		anim_state.setAnimation(String(anim_name), loop, 0)
	# 标记攻击动画播放状态
	_attack_anim_playing = (anim_name == &"attack")


func anim_is_finished(anim_name: StringName) -> bool:
	## 轮询兜底：检查指定动画是否已播完（SPINE §2.3）
	if _spine == null:
		return true
	if _current_anim != anim_name:
		return true
	var anim_state: Object = null
	if _spine.has_method("get_animation_state"):
		anim_state = _spine.get_animation_state()
	elif _spine.has_method("getAnimationState"):
		anim_state = _spine.getAnimationState()
	if anim_state == null:
		return true
	var entry: Object = null
	if anim_state.has_method("get_current"):
		entry = anim_state.get_current(0)
	elif anim_state.has_method("getCurrent"):
		entry = anim_state.getCurrent(0)
	if entry == null:
		return true
	if entry.has_method("is_complete"):
		return entry.is_complete()
	elif entry.has_method("isComplete"):
		return entry.isComplete()
	return false


# 使用 animation_completed（不是 animation_ended）（SPINE §2.5）
func _on_anim_completed_raw(a1 = null, a2 = null, a3 = null) -> void:
	var anim_name: StringName = _extract_completed_anim_name(a1, a2, a3)
	if anim_name == &"attack":
		_attack_anim_playing = false
	if _dying and anim_name == &"death":
		queue_free()
	elif _being_hunted and anim_name == &"hunted":
		queue_free()


func _extract_completed_anim_name(a1 = null, a2 = null, a3 = null) -> StringName:
	var entry: Object = null
	for a in [a1, a2, a3]:
		if a == null:
			continue
		if a is Object and a.has_method("get_animation"):
			entry = a
			break
		if a is Object and a.has_method("getAnimation"):
			entry = a
			break
	if entry == null:
		return &""
	var anim: Object = null
	if entry.has_method("get_animation"):
		anim = entry.get_animation()
	elif entry.has_method("getAnimation"):
		anim = entry.getAnimation()
	if anim == null:
		return &""
	var name_str: String = ""
	if anim.has_method("get_name"):
		name_str = anim.get_name()
	elif anim.has_method("getName"):
		name_str = anim.getName()
	if name_str == "":
		return &""
	return StringName(name_str)


func _on_spine_event(a1 = null, a2 = null, a3 = null, a4 = null) -> void:
	## Spine 动画事件回调：处理 atk_hit_on / atk_hit_off
	var event_obj: Object = null
	for a in [a1, a2, a3, a4]:
		if a == null:
			continue
		if a is Object and (a.has_method("get_data") or a.has_method("getData")):
			event_obj = a
			break
	if event_obj == null:
		return
	var event_data: Object = null
	if event_obj.has_method("get_data"):
		event_data = event_obj.get_data()
	elif event_obj.has_method("getData"):
		event_data = event_obj.getData()
	if event_data == null:
		return
	var event_name: String = ""
	if event_data.has_method("get_name"):
		event_name = event_data.get_name()
	elif event_data.has_method("getName"):
		event_name = event_data.getName()
	match event_name:
		"atk_hit_on":
			set_attack_hitbox_active(true)
		"atk_hit_off":
			set_attack_hitbox_active(false)


# =============================================================================
# 移动（由 Beehave 行为树控制，不使用 _do_move）
# =============================================================================
func _do_move(_dt: float) -> void:
	pass


# =============================================================================
# 朝向与辅助查询
# =============================================================================
const FACE_DEAD_ZONE: float = 30.0

func face_toward(target: Node2D) -> void:
	if target == null:
		return
	var dir: float = target.global_position.x - global_position.x
	if absf(dir) <= FACE_DEAD_ZONE:
		return
	if _spine != null:
		_spine.scale.x = absf(_spine.scale.x) * (1.0 if dir > 0.0 else -1.0)
	elif sprite != null:
		sprite.flip_h = dir < 0.0


func is_player_in_detect_area() -> bool:
	var detect: Area2D = get_node_or_null("DetectArea") as Area2D
	if detect == null:
		return false
	for body in detect.get_overlapping_bodies():
		if body.is_in_group("player"):
			return true
	return false


func is_player_in_attack_area() -> bool:
	var attack: Area2D = get_node_or_null("AttackArea") as Area2D
	if attack == null:
		return false
	for body in attack.get_overlapping_bodies():
		if body.is_in_group("player"):
			return true
	return false


func get_player_node() -> Node2D:
	var players: Array[Node] = get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return null
	var p: Node2D = players[0] as Node2D
	if p != null and is_instance_valid(p):
		return p
	return null
