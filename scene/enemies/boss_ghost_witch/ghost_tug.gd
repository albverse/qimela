extends Node2D
class_name GhostTug

## 幽灵拔河：绑定玩家，每帧拉拽玩家向 Boss 移动
## 被 ghostfist 打中 → 播放 hit 渐隐 → 销毁
## 透明度渐显/渐隐全部由 Spine 动画控制

var _player: Node2D = null
var _boss: Node2D = null
var _pull_speed: float = 400.0
var _dying: bool = false
var _appeared: bool = false
var _current_anim: StringName = &""
var _current_anim_finished: bool = false
var _current_anim_loop: bool = false

func setup(player: Node2D, boss: Node2D, pull_speed: float) -> void:
	_player = player
	_boss = boss
	_pull_speed = pull_speed

func _ready() -> void:
	_play_anim(&"appear", false)

	var spine: Node = get_node_or_null("SpineSprite")
	if spine and spine.has_signal("animation_event"):
		spine.animation_event.connect(_on_spine_event)
	if spine and spine.has_signal("animation_completed"):
		spine.animation_completed.connect(_on_anim_completed_raw)

	var hit_area: Area2D = get_node_or_null("HitArea")
	if hit_area:
		hit_area.area_entered.connect(_on_hit)

func _on_anim_completed_raw(_spine_sprite: Variant, _track_entry: Variant) -> void:
	_current_anim_finished = true
	if not _appeared and not _dying:
		_appeared = true
		_play_anim(&"move_loop", true)
		return
	if _dying:
		queue_free()

func _on_spine_event(a1: Variant, a2: Variant, a3: Variant, a4: Variant) -> void:
	if _dying:
		return
	var event_name: StringName = _extract_event_name(a1, a2, a3, a4)
	if event_name == &"move":
		_pull_player_toward_boss()

func _pull_player_toward_boss() -> void:
	if _player == null or _boss == null:
		return
	if not is_instance_valid(_player) or not is_instance_valid(_boss):
		return
	var dir_x: float = signf(_boss.global_position.x - _player.global_position.x)
	_player.velocity.x = dir_x * _pull_speed
	if _player.has_method("set_external_control_frozen"):
		_player.call("set_external_control_frozen", true)

func _on_hit(area: Area2D) -> void:
	if _dying:
		return
	if not area.is_in_group("ghost_fist_hitbox"):
		return
	_dying = true
	_release_player()
	_play_anim(&"hit", false)

func _release_player() -> void:
	if _player and is_instance_valid(_player) and _player.has_method("set_external_control_frozen"):
		_player.call("set_external_control_frozen", false)

func _exit_tree() -> void:
	_release_player()

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
