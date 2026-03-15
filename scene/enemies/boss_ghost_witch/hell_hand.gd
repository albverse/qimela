extends Node2D
class_name HellHand

## 地狱之手：禁锢陷阱
## appear 动画中 capture_check 事件决定是否抓住玩家
## hold 循环直到禁锢时间结束或被 ghostfist 打碎
## close 动画播完后销毁

enum HandState { APPEAR, HOLD, CLOSING }

var _state: int = HandState.APPEAR
var _player: Node2D = null
var _boss: Node2D = null
var _stun_time: float = 3.0
var _imprison_end: float = 0.0
var _player_captured: bool = false
var _current_anim: StringName = &""
var _current_anim_finished: bool = false
var _current_anim_loop: bool = false

func setup(player: Node2D, boss: Node2D, _escape_time: float, stun_time: float) -> void:
	_player = player
	_boss = boss
	_stun_time = stun_time

func _ready() -> void:
	add_to_group("hell_hand")
	_state = HandState.APPEAR
	_play_anim(&"appear", false)

	var spine: Node = get_node_or_null("SpineSprite")
	if spine and spine.has_signal("animation_event"):
		spine.animation_event.connect(_on_spine_event)
	if spine and spine.has_signal("animation_completed"):
		spine.animation_completed.connect(_on_anim_completed_raw)

	var hit_area: Area2D = get_node_or_null("HitArea")
	if hit_area:
		hit_area.area_entered.connect(_on_ghostfist_hit)

func _on_anim_completed_raw(_ss: Variant, _te: Variant) -> void:
	_current_anim_finished = true

func _on_spine_event(a1: Variant, a2: Variant, a3: Variant, a4: Variant) -> void:
	var event_name: StringName = _extract_event_name(a1, a2, a3, a4)
	match event_name:
		&"capture_check":
			if _is_player_in_capture_area():
				_capture_player()
			else:
				_state = HandState.CLOSING
				_play_anim(&"close", false)

func _physics_process(_dt: float) -> void:
	match _state:
		HandState.APPEAR:
			if _current_anim == &"appear" and _current_anim_finished and not _player_captured:
				_state = HandState.CLOSING
				_play_anim(&"close", false)
		HandState.HOLD:
			if Time.get_ticks_msec() >= _imprison_end:
				_release_player()
				_state = HandState.CLOSING
				_play_anim(&"close", false)
		HandState.CLOSING:
			if _current_anim == &"close" and _current_anim_finished:
				_cleanup_and_free()

func _is_player_in_capture_area() -> bool:
	var capture_area: Area2D = get_node_or_null("CaptureArea")
	if capture_area == null:
		return false
	for body: Node2D in capture_area.get_overlapping_bodies():
		if body.is_in_group("player"):
			return true
	return false

func _capture_player() -> void:
	_player_captured = true
	_state = HandState.HOLD
	_imprison_end = Time.get_ticks_msec() + _stun_time * 1000.0
	_play_anim(&"hold", true)
	if _player and is_instance_valid(_player):
		if _player.has_method("set_external_control_frozen"):
			_player.call("set_external_control_frozen", true)
	if _boss and is_instance_valid(_boss):
		_boss._player_imprisoned = true

func _release_player() -> void:
	_player_captured = false
	if _player and is_instance_valid(_player):
		if _player.has_method("set_external_control_frozen"):
			_player.call("set_external_control_frozen", false)
	if _boss and is_instance_valid(_boss):
		_boss._player_imprisoned = false

func _on_ghostfist_hit(area: Area2D) -> void:
	if area.is_in_group("ghost_fist_hitbox"):
		_release_player()
		_state = HandState.CLOSING
		_play_anim(&"close", false)

func _cleanup_and_free() -> void:
	_release_player()
	queue_free()

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
