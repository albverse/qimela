## 幽灵拔河：生成在Boss身后，面朝玩家，通过Spine事件脉冲拉拽玩家靠近Boss
## 动画流程：appear → move_loop（循环）→ hit（被 ghostfist 击中后消失）
## 拉力由 Spine 事件 "move" 触发脉冲式推动（非每帧连续）
extends MonsterBase
class_name GhostTug

@export var pull_speed: float = 400.0
@export var opposite_move_multiplier: float = 0.33
var _player: Node2D = null
var _boss: Node2D = null
var _dying: bool = false
var _pulling: bool = false  # appear 完成后开始拉扯
var _follow_offset_x: float = 60.0

var _spine: Node = null

func _ready() -> void:
	species_id = &"ghost_tug"
	has_hp = false
	super._ready()
	add_to_group("ghost_tug")
	add_to_group("ghost")

	_spine = get_node_or_null("SpineSprite")
	if _spine != null:
		if _spine.has_signal("animation_completed"):
			_spine.animation_completed.connect(_on_anim_completed_raw)
		if _spine.has_signal("animation_event"):
			_spine.animation_event.connect(_on_spine_event)
	# 播放出现动画
	_spine_play(&"appear", false)
	# 0.5 秒后强制开始拉扯（防止 appear 动画不触发完成信号）
	get_tree().create_timer(0.5).timeout.connect(_force_start_pull)
	print("[GHOST_TUG_DEBUG] _ready: spawned at global_pos=%s" % global_position)


func setup(player: Node2D, boss: Node2D, pull_speed_override: float = -1.0) -> void:
	_player = player
	_boss = boss
	if pull_speed_override > 0.0:
		pull_speed = pull_speed_override
	# 面朝玩家方向（基于 GhostTug 自身位置，而非 Boss）
	if _spine != null and player != null:
		var dx: float = player.global_position.x - global_position.x
		if is_zero_approx(dx):
			dx = 1.0
		_spine.scale.x = absf(_spine.scale.x) * (1.0 if dx > 0.0 else -1.0)


func apply_hit(hit: HitData) -> bool:
	if _dying:
		return false
	if hit == null or hit.weapon_id != &"ghost_fist":
		return false
	_dying = true
	_pulling = false
	_release_player()
	_spine_play(&"hit", false)
	print("[GHOST_TUG_DEBUG] hit by ghostfist, dying")
	# 0.5 秒后强制释放（防止 hit 动画不触发完成信号）
	get_tree().create_timer(0.5).timeout.connect(queue_free)
	return true


func _physics_process(dt: float) -> void:
	# 持续拉力 + 逆向移动限速；Spine 事件额外脉冲加强手感
	if _dying or not _pulling:
		return
	if _player == null or _boss == null:
		return
	if not is_instance_valid(_player) or not is_instance_valid(_boss):
		return
	var dir_x: float = signf(_boss.global_position.x - _player.global_position.x)
	if is_zero_approx(dir_x):
		dir_x = 1.0
	# 立绘节点始终跟随玩家，保持在玩家->Boss方向的前方
	global_position = Vector2(_player.global_position.x + dir_x * _follow_offset_x, _player.global_position.y)
	if "velocity" in _player:
		_player.velocity.x = dir_x * pull_speed
	if _player.has_method("set_external_pull_constraint"):
		_player.call("set_external_pull_constraint", true, dir_x, opposite_move_multiplier)
	if _player.has_method("set_external_pull_velocity_x"):
		_player.call("set_external_pull_velocity_x", dir_x * pull_speed)
	if Engine.get_physics_frames() % 20 == 0:
		print("[GHOST_TUG_DEBUG] sustain_pull: dir=%s speed=%s tug_pos=%s player=%s boss=%s dt=%.3f" % [dir_x, pull_speed, global_position, _player.global_position, _boss.global_position, dt])


func _force_start_pull() -> void:
	if not _dying and not _pulling:
		_pulling = true
		_spine_play(&"move_loop", true)
		print("[GHOST_TUG_DEBUG] force_start_pull: pulling started")


func _on_anim_completed_raw(a1 = null, a2 = null, a3 = null) -> void:
	var anim_name := _extract_completed_anim_name(a1, a2, a3)
	if anim_name == &"appear" and not _pulling and not _dying:
		_pulling = true
		_spine_play(&"move_loop", true)
		print("[GHOST_TUG_DEBUG] appear completed, starting pull")
	elif anim_name == &"hit":
		queue_free()


func _on_spine_event(a1 = null, a2 = null, a3 = null, a4 = null) -> void:
	if _dying or not _pulling:
		return
	var e := _extract_spine_event_name(a1, a2, a3, a4)
	if e == &"move":
		_pull_player_toward_boss()


func _pull_player_toward_boss() -> void:
	## 脉冲式拉拽：每次 Spine "move" 事件触发时，给玩家一个朝向 Boss 的速度冲量
	if _player == null or _boss == null:
		return
	if not is_instance_valid(_player) or not is_instance_valid(_boss):
		return
	var dir_x: float = signf(_boss.global_position.x - _player.global_position.x)
	if dir_x == 0.0:
		dir_x = 1.0
	# 设置朝向 Boss 的水平速度脉冲
	if "velocity" in _player:
		_player.velocity.x = dir_x * pull_speed
	if _player.has_method("set_external_pull_constraint"):
		_player.call("set_external_pull_constraint", true, dir_x, opposite_move_multiplier)
	if _player.has_method("set_external_pull_velocity_x"):
		_player.call("set_external_pull_velocity_x", dir_x * pull_speed)
	print("[GHOST_TUG_DEBUG] pull_pulse: dir=%s speed=%s player_pos=%s boss_pos=%s" % [dir_x, pull_speed, _player.global_position, _boss.global_position])




func begin_despawn(duration_sec: float = 0.5) -> void:
	if _dying:
		return
	_dying = true
	_pulling = false
	_release_player()
	print("[GHOST_TUG_DEBUG] begin_despawn duration=%.2f pos=%s" % [duration_sec, global_position])
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, maxf(duration_sec, 0.01))
	tw.finished.connect(queue_free)

func _release_player() -> void:
	if _player != null and is_instance_valid(_player):
		if _player.has_method("set_external_control_frozen"):
			_player.call("set_external_control_frozen", false)
		if _player.has_method("clear_external_pull_constraint"):
			_player.call("clear_external_pull_constraint")
		if _player.has_method("set_external_pull_velocity_x"):
			_player.call("set_external_pull_velocity_x", 0.0)


func _exit_tree() -> void:
	_release_player()


# ═══ Spine 播放 + 事件名/动画名提取 ═══

func _spine_play(anim_name: StringName, loop: bool) -> void:
	if _spine == null:
		return
	var anim_state: Object = null
	if _spine.has_method("get_animation_state"):
		anim_state = _spine.get_animation_state()
	if anim_state != null and anim_state.has_method("set_animation"):
		anim_state.set_animation(String(anim_name), loop, 0)


func _extract_spine_event_name(a1 = null, a2 = null, a3 = null, a4 = null) -> StringName:
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
