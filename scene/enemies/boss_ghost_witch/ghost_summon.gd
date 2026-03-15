extends Node2D
class_name GhostSummon

## 召唤幽灵：地面圆圈 → 延迟后幽灵飞出
## HitArea 绑定 ghost 骨骼，Spine 事件控制启闭
## 自然消失，不可被 ghostfist 消灭

var _delay: float = 0.3
var _spawned: bool = false
var _lifetime: float = 3.0
var _ghost_hit_area: Area2D = null
var _current_anim: StringName = &""
var _current_anim_finished: bool = false
var _current_anim_loop: bool = false

func setup(delay: float) -> void:
	_delay = delay

func _ready() -> void:
	add_to_group("ghost_summon")
	_ghost_hit_area = get_node_or_null("GhostHitArea")
	_play_anim(&"circle_appear", false)
	_set_hitarea_enabled(false)

	var spine: Node = get_node_or_null("SpineSprite")
	if spine and spine.has_signal("animation_event"):
		spine.animation_event.connect(_on_spine_event)
	if spine and spine.has_signal("animation_completed"):
		spine.animation_completed.connect(_on_anim_completed_raw)

	if _ghost_hit_area:
		_ghost_hit_area.body_entered.connect(_on_body_entered)

func _on_anim_completed_raw(_ss: Variant, _te: Variant) -> void:
	_current_anim_finished = true

func _physics_process(dt: float) -> void:
	if not _spawned:
		_delay -= dt
		if _delay <= 0.0:
			_spawned = true
			_play_anim(&"ghost_fly_out", false)
	else:
		_lifetime -= dt
		if _lifetime <= 0.0:
			queue_free()
			return
	_sync_hitarea_to_bone()

func _on_spine_event(a1: Variant, a2: Variant, a3: Variant, a4: Variant) -> void:
	var event_name: StringName = _extract_event_name(a1, a2, a3, a4)
	match event_name:
		&"ghost_hitbox_on":
			_set_hitarea_enabled(true)
		&"ghost_hitbox_off":
			_set_hitarea_enabled(false)

func _sync_hitarea_to_bone() -> void:
	if _ghost_hit_area == null:
		return
	var spine: Node = get_node_or_null("SpineSprite")
	if spine == null:
		return
	if spine.has_method("get_skeleton"):
		var skeleton: Variant = spine.get_skeleton()
		if skeleton and skeleton.has_method("find_bone"):
			var bone: Variant = skeleton.find_bone("ghost")
			if bone:
				if bone.has_method("get_world_position_x") and bone.has_method("get_world_position_y"):
					var bone_pos: Vector2 = Vector2(bone.get_world_position_x(), bone.get_world_position_y())
					_ghost_hit_area.position = bone_pos

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player") and body.has_method("apply_damage"):
		body.call("apply_damage", 1, global_position)

func _set_hitarea_enabled(enabled: bool) -> void:
	if _ghost_hit_area == null:
		return
	_ghost_hit_area.set_deferred("monitoring", enabled)
	for child: Node in _ghost_hit_area.get_children():
		if child is CollisionShape2D:
			child.set_deferred("disabled", not enabled)

func _play_anim(anim_name: StringName, loop: bool) -> void:
	if _current_anim == anim_name and not _current_anim_finished and _current_anim_loop == loop:
		return
	_current_anim = anim_name
	_current_anim_finished = false
	_current_anim_loop = loop
	var spine: Node = get_node_or_null("SpineSprite")
	if spine == null:
		return
	var anim_state: Variant = null
	if spine.has_method("get_animation_state"):
		anim_state = spine.get_animation_state()
	if anim_state and anim_state.has_method("set_animation"):
		anim_state.set_animation(anim_name, loop, 0)

func _extract_event_name(a1: Variant, a2: Variant, a3: Variant, a4: Variant) -> StringName:
	for a: Variant in [a1, a2, a3, a4]:
		if a is Object and a.has_method("get_data"):
			var data: Variant = a.get_data()
			if data != null and data.has_method("get_event_name"):
				return StringName(data.get_event_name())
	return &""
