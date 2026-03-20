extends Node2D
class_name GhostWraith

## 亡灵气流幽灵（3型合一）：type 1/2/3 决定不同动画
## 向玩家方向平移，碰到玩家伤害，被 ghostfist 打中播死亡动画后销毁
## 最多存活 10 秒后自动消失

var _type: int = 1
var _player: Node2D = null
var _dying: bool = false
var _move_speed: float = 80.0
var _lifetime: float = 10.0
var _current_anim: StringName = &""
var _current_anim_finished: bool = false
var _current_anim_loop: bool = false
var _hit_player: bool = false

func setup(type: int, player: Node2D, _spawn_pos: Vector2) -> void:
	_type = type
	_player = player

func _ready() -> void:
	add_to_group("ghost_wraith")
	var move_anim: StringName = StringName("type%d/move" % _type)
	_play_anim(move_anim, true)

	var hit_area: Area2D = get_node_or_null("HitArea")
	if hit_area:
		hit_area.area_entered.connect(_on_hit_by_ghostfist)
		hit_area.body_entered.connect(_on_body_entered)

	var spine: Node = get_node_or_null("SpineSprite")
	if spine and spine.has_signal("animation_completed"):
		spine.animation_completed.connect(_on_anim_completed_raw)

func _on_anim_completed_raw(_ss: Variant, _te: Variant) -> void:
	_current_anim_finished = true
	if _dying:
		queue_free()

func _physics_process(dt: float) -> void:
	if _dying:
		return
	_lifetime -= dt
	if _lifetime <= 0.0:
		queue_free()
		return
	if _player == null or not is_instance_valid(_player):
		return
	var dir: float = signf(_player.global_position.x - global_position.x)
	global_position.x += dir * _move_speed * dt

func _on_body_entered(body: Node2D) -> void:
	if _dying or _hit_player:
		return
	if body.is_in_group("player") and body.has_method("apply_damage"):
		body.call("apply_damage", 1, global_position)
		_hit_player = true

func _on_hit_by_ghostfist(area: Area2D) -> void:
	if _dying:
		return
	if not area.is_in_group("ghost_fist_hitbox"):
		return
	_dying = true
	set_physics_process(false)
	var death_anim: StringName = StringName("type%d/death" % _type)
	_play_anim(death_anim, false)

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
