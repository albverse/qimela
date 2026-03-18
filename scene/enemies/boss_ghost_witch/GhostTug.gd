## 幽灵拔河：生成在Boss身后，面朝玩家，通过Spine事件脉冲弹射玩家
## 动画流程：appear → move_loop（循环）→ hit（被 ghostfist 击中后消失）
## 每次 Spine "move" 事件触发一次 20px 弹射（受伤击飞手感），弹射期间禁用 WASD
extends MonsterBase
class_name GhostTug

@export var knockback_distance_px: float = 240.0
@export var knockback_duration: float = 0.35
@export var knockback_vertical_impulse: float = -800.0  # 向上弹起（负值=向上）
var _player: Node2D = null
var _boss: Node2D = null
var _dying: bool = false
var _pulling: bool = false  # appear 完成后开始拉扯
var _follow_offset_x: float = 60.0
var _knockback_tween: Tween = null

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


func setup(player: Node2D, boss: Node2D, _pull_speed_override: float = -1.0) -> void:
	_player = player
	_boss = boss
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


func _physics_process(_dt: float) -> void:
	# 不再每帧施加持续拉力，仅跟随玩家位置（立绘保持在玩家→Boss方向前方）
	if _dying or not _pulling:
		return
	if _player == null or _boss == null:
		return
	if not is_instance_valid(_player) or not is_instance_valid(_boss):
		return
	var dir_x: float = signf(_boss.global_position.x - _player.global_position.x)
	if is_zero_approx(dir_x):
		dir_x = 1.0
	global_position = Vector2(_player.global_position.x + dir_x * _follow_offset_x, _player.global_position.y)


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
		_knockback_player()


func _knockback_player() -> void:
	## 弹射脉冲：每次 Spine "move" 事件触发时，将玩家弹射 20px（受伤击飞手感）
	## 弹射期间禁用所有 WASD 输入
	if _player == null or _boss == null:
		return
	if not is_instance_valid(_player) or not is_instance_valid(_boss):
		return
	var dir_x: float = signf(_boss.global_position.x - _player.global_position.x)
	if dir_x == 0.0:
		dir_x = 1.0
	# 计算弹射初速度：distance = v0 * t / 2（匀减速近似）→ v0 = 2 * dist / t
	var kb_speed: float = 2.0 * knockback_distance_px / maxf(knockback_duration, 0.01)
	# 冻结玩家输入
	if _player.has_method("set_external_control_frozen"):
		_player.call("set_external_control_frozen", true)
	# 设置弹射速度（通过 tug_knockback_vx，在 PlayerMovement.tick 中覆盖一切水平输入）
	if _player.has_method("set_tug_knockback_vx"):
		_player.call("set_tug_knockback_vx", dir_x * kb_speed)
	# 垂直弹起（受伤被弹飞效果）
	if "velocity" in _player:
		_player.velocity.y = knockback_vertical_impulse
	print("[GHOST_TUG_DEBUG] knockback_pulse: dir=%s speed=%.1f dist=%.1f duration=%.3f vy=%.1f player_pos=%s boss_pos=%s" % [dir_x, kb_speed, knockback_distance_px, knockback_duration, knockback_vertical_impulse, _player.global_position, _boss.global_position])
	# Tween 衰减速度到 0，完成后解冻玩家
	if _knockback_tween != null and _knockback_tween.is_valid():
		_knockback_tween.kill()
	_knockback_tween = create_tween()
	# 线性衰减弹射速度（匀减速效果）
	_knockback_tween.tween_method(_update_knockback_vx.bind(dir_x), kb_speed, 0.0, knockback_duration)
	_knockback_tween.finished.connect(_on_knockback_finished)


func _update_knockback_vx(speed_abs: float, dir_x: float) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	if _player.has_method("set_tug_knockback_vx"):
		_player.call("set_tug_knockback_vx", dir_x * speed_abs)


func _on_knockback_finished() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	# 清除弹射速度
	if _player.has_method("set_tug_knockback_vx"):
		_player.call("set_tug_knockback_vx", 0.0)
	# 解冻玩家输入（仅在 GhostTug 仍存活时才由自己解冻，否则由 _release_player 处理）
	if not _dying:
		if _player.has_method("set_external_control_frozen"):
			_player.call("set_external_control_frozen", false)
	print("[GHOST_TUG_DEBUG] knockback_finished: player_pos=%s dying=%s" % [_player.global_position, _dying])


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
	if _knockback_tween != null and _knockback_tween.is_valid():
		_knockback_tween.kill()
		_knockback_tween = null
	if _player != null and is_instance_valid(_player):
		if _player.has_method("set_tug_knockback_vx"):
			_player.call("set_tug_knockback_vx", 0.0)
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
