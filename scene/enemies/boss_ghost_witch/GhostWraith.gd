extends MonsterBase
class_name GhostWraith

@export var speed: float = 80.0
@export var lifetime: float = 10.0

var _t: float = 0.0
var _type: int = 1
var _dying: bool = false
var _player: Node2D = null
var _fly_dir: float = 1.0  # 飞行方向（+1 向右，-1 向左），在 setup 时确定，之后不变

var _spine: Node = null
var _current_anim: StringName = &""

func _ready() -> void:
	species_id = &"ghost_wraith"
	has_hp = false
	super._ready()
	add_to_group("ghost_wraith")
	add_to_group("ghost")

	_spine = get_node_or_null("SpineSprite")
	if _spine != null and _spine.has_signal("animation_completed"):
		_spine.animation_completed.connect(_on_anim_completed_raw)

	_play_anim(_move_anim(), true)


func setup(wraith_type: int, player: Node2D, spawn_pos: Vector2) -> void:
	_type = clampi(wraith_type, 1, 3)
	_player = player
	# 飞行方向：Boss 面朝玩家的方向（从 spawn_pos 指向玩家），确定后不再改变
	if player != null:
		var dx: float = player.global_position.x - spawn_pos.x
		_fly_dir = 1.0 if dx >= 0.0 else -1.0
	else:
		_fly_dir = 1.0
	# 翻转 Spine 朝向飞行方向
	if _spine != null:
		_spine.scale.x = absf(_spine.scale.x) * _fly_dir


func _physics_process(dt: float) -> void:
	if _dying:
		return
	_t += dt
	if _t >= lifetime:
		queue_free()
		return

	# 直线飞行（方向在 setup 时固定，不追踪玩家）
	global_position.x += _fly_dir * speed * dt

	# 碰到玩家造成伤害
	if _player != null and is_instance_valid(_player):
		if global_position.distance_to(_player.global_position) < 22.0 and _player.has_method("apply_damage"):
			_player.call("apply_damage", 1, global_position)


func apply_hit(hit: HitData) -> bool:
	if _dying:
		return false
	if hit == null or hit.weapon_id != &"ghost_fist":
		return false
	_dying = true
	_play_anim(_death_anim(), false)
	print("[GHOST_WRAITH_DEBUG] hit by ghostfist, type=%d" % _type)
	return true


func _on_anim_completed_raw(a1 = null, a2 = null, a3 = null) -> void:
	if not _dying:
		return
	var anim_name := _extract_completed_anim_name(a1, a2, a3)
	if anim_name == _death_anim():
		queue_free()


func _move_anim() -> StringName:
	return StringName("type%d/move" % _type)


func _death_anim() -> StringName:
	return StringName("type%d/death" % _type)


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
	if anim_state.has_method("set_animation"):
		anim_state.set_animation(String(anim_name), loop, 0)
	elif anim_state.has_method("setAnimation"):
		anim_state.setAnimation(String(anim_name), loop, 0)


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
