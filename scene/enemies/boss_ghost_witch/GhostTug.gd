## 幽灵拔河：绑定到玩家身上，通过 Spine 事件 "move" 驱动拉扯
## 动画流程：appear → move_loop（循环，"move"事件触发拉力）→ hit（被 ghostfist 击中后播放消失）
extends MonsterBase
class_name GhostTug

@export var pull_speed: float = 400.0
var _player: Node2D = null
var _boss: Node2D = null
var _dying: bool = false

var _spine: Node = null
var _current_anim: StringName = &""
var _current_anim_finished: bool = false

func _ready() -> void:
	species_id = &"ghost_tug"
	has_hp = false
	super._ready()
	add_to_group("ghost_tug")

	_spine = get_node_or_null("SpineSprite")
	if _spine != null:
		if _spine.has_signal("animation_completed"):
			_spine.animation_completed.connect(_on_anim_completed_raw)
		if _spine.has_signal("animation_event"):
			_spine.animation_event.connect(_on_spine_event)
	# 播放出现动画
	_spine_play(&"appear", false)


func setup(player: Node2D, boss: Node2D) -> void:
	_player = player
	_boss = boss


func apply_hit(hit: HitData) -> bool:
	if _dying:
		return false
	if hit == null or hit.weapon_id != &"ghost_fist":
		return false
	_dying = true
	_release_player()
	_spine_play(&"hit", false)
	# hit 动画播完后 _on_anim_completed_raw 会 queue_free
	return true


# ═══ Spine 事件：move 事件触发拉力 ═══

func _on_spine_event(a1 = null, a2 = null, a3 = null, a4 = null) -> void:
	var e := _extract_event_name(a1, a2, a3, a4)
	if e == &"move" and not _dying:
		_do_pull()


func _on_anim_completed_raw(a1 = null, a2 = null, a3 = null) -> void:
	var anim_name := _extract_completed_anim_name(a1, a2, a3)
	if anim_name == &"appear":
		_spine_play(&"move_loop", true)
	elif anim_name == &"hit":
		queue_free()


func _do_pull() -> void:
	if _player == null or _boss == null:
		return
	if not is_instance_valid(_player) or not is_instance_valid(_boss):
		return
	if _player.has_method("set_external_control_frozen"):
		_player.call("set_external_control_frozen", true)
	if "velocity" in _player:
		var dir := signf(_boss.global_position.x - _player.global_position.x)
		_player.velocity.x = dir * pull_speed


func _release_player() -> void:
	if _player != null and is_instance_valid(_player):
		if _player.has_method("set_external_control_frozen"):
			_player.call("set_external_control_frozen", false)


func _exit_tree() -> void:
	_release_player()


# ═══ Spine 播放 + 事件提取（与 BossGhostWitch 同款） ═══

func _spine_play(anim_name: StringName, loop: bool) -> void:
	if _spine == null:
		return
	_current_anim = anim_name
	_current_anim_finished = false
	var anim_state: Object = null
	if _spine.has_method("get_animation_state"):
		anim_state = _spine.get_animation_state()
	if anim_state != null and anim_state.has_method("set_animation"):
		anim_state.set_animation(String(anim_name), loop, 0)


func _extract_event_name(a1 = null, a2 = null, a3 = null, a4 = null) -> StringName:
	var spine_event: Object = null
	for a in [a1, a2, a3, a4]:
		if a == null:
			continue
		if a is Object and a.has_method("get_data"):
			spine_event = a
			break
	if spine_event == null:
		return &""
	var data: Object = spine_event.get_data()
	if data == null:
		return &""
	var event_name: String = ""
	if data.has_method("get_event_name"):
		event_name = data.get_event_name()
	elif data.has_method("getEventName"):
		event_name = data.getEventName()
	elif data.has_method("get_name"):
		event_name = data.get_name()
	elif data.has_method("getName"):
		event_name = data.getName()
	if event_name == "":
		return &""
	return StringName(event_name)


func _extract_completed_anim_name(a1 = null, a2 = null, a3 = null) -> StringName:
	## 从 animation_completed 信号的 track_entry 参数中提取动画名
	var entry: Object = null
	for a in [a1, a2, a3]:
		if a == null:
			continue
		if a is Object and a.has_method("get_animation"):
			entry = a
			break
	if entry == null:
		return &""
	var anim: Object = null
	if entry.has_method("get_animation"):
		anim = entry.get_animation()
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
