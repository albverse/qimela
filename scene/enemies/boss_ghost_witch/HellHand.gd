## 地狱之手：在玩家位置出现 → appear 动画播 capture_check 事件 → 抓住或收回
## 生命周期：APPEAR → (capture_check) → HOLD/CLOSING → (close完成) → queue_free
## 按蓝图规范：_physics_process 轮询动画状态驱动状态机，Spine 事件作为辅助
extends MonsterBase
class_name HellHand

enum HandState { APPEAR, HOLD, CLOSING }

var _state: int = HandState.APPEAR
var _player: Node2D = null
var _boss: BossGhostWitch = null
var _imprison_end: int = 0
var _stun_time: float = 3.0
var _player_captured: bool = false

var _spine: Node = null
var _capture_area: Area2D = null
var _hit_area: Area2D = null

# 当前播放的动画名和完成状态（轮询用）
var _current_anim_name: StringName = &""
var _current_anim_loop: bool = false

# 备用捕获：距离检测（防止 Spine 事件或 Area2D 时序问题导致漏捕）
var _appear_elapsed: float = 0.0
const CAPTURE_FALLBACK_TIME: float = 0.25  # appear 播放 0.25s 后做距离备用检测
const CAPTURE_FALLBACK_RADIUS: float = 55.0  # 备用捕获半径（px）
var _fallback_capture_done: bool = false


func _ready() -> void:
	species_id = &"hell_hand"
	has_hp = false
	super._ready()
	add_to_group("hell_hand")

	_spine = get_node_or_null("SpineSprite")
	_capture_area = get_node_or_null("CaptureArea")
	_hit_area = get_node_or_null("HitArea")

	if _spine != null:
		var has_completed := _spine.has_signal("animation_completed")
		var has_event := _spine.has_signal("animation_event")
		print("[HELL_HAND_DEBUG] _ready: spine found, animation_completed=%s animation_event=%s spine_class=%s pos=%s" % [has_completed, has_event, _spine.get_class(), global_position])
		if has_completed:
			_spine.animation_completed.connect(_on_anim_completed_raw)
		if has_event:
			_spine.animation_event.connect(_on_spine_event)
	else:
		print("[HELL_HAND_DEBUG] _ready: SpineSprite NOT found! children=%s pos=%s" % [_list_children(), global_position])

	# 按蓝图连接 HitArea 的 area_entered 信号用于 ghostfist 击碎检测
	if _hit_area != null:
		_hit_area.area_entered.connect(_on_ghostfist_hit)
		print("[HELL_HAND_DEBUG] _ready: HitArea connected area_entered signal")
	else:
		print("[HELL_HAND_DEBUG] _ready: HitArea NOT found, ghostfist hit via apply_hit only")

	_appear_elapsed = 0.0
	_fallback_capture_done = false
	_play_anim(&"appear", false)
	print("[HELL_HAND_DEBUG] _ready complete: state=%d pos=%s" % [_state, global_position])


func setup(player: Node2D, boss: BossGhostWitch, stun_time: float) -> void:
	_player = player
	_boss = boss
	_stun_time = stun_time
	print("[HELL_HAND_DEBUG] setup: player=%s boss=%s stun_time=%.2f" % [player, boss, stun_time])


# ═══ Spine 事件回调（辅助机制，按蓝图 capture_check 事件驱动捕获判定）═══

func _on_spine_event(a1 = null, a2 = null, a3 = null, a4 = null) -> void:
	var event_name := _extract_spine_event_name(a1, a2, a3, a4)
	print("[HELL_HAND_DEBUG] spine_event: name=%s state=%d captured=%s" % [event_name, _state, _player_captured])
	if event_name != &"capture_check":
		return
	if _state != HandState.APPEAR:
		print("[HELL_HAND_DEBUG] capture_check ignored: state=%d (not APPEAR)" % _state)
		return
	if _is_player_in_capture_area():
		print("[HELL_HAND_DEBUG] capture_check: player IN area → capture + hold")
		_capture_player()
	else:
		print("[HELL_HAND_DEBUG] capture_check: player NOT in area → close")
		_state = HandState.CLOSING
		_play_anim(&"close", false)


func _on_anim_completed_raw(a1 = null, a2 = null, a3 = null) -> void:
	var anim_name := _extract_completed_anim_name(a1, a2, a3)
	print("[HELL_HAND_DEBUG] anim_completed_signal: name=%s state=%d captured=%s current_anim=%s" % [anim_name, _state, _player_captured, _current_anim_name])
	# 信号回调只用于日志跟踪，状态转换由 _physics_process 轮询驱动


# ═══ _physics_process：按蓝图轮询动画状态驱动状态机 ═══

func _physics_process(_dt: float) -> void:
	# 每 60 帧输出一次状态诊断
	if Engine.get_physics_frames() % 60 == 0:
		var track_info := _get_track_debug_info()
		print("[HELL_HAND_DIAG] state=%d captured=%s anim=%s track=%s pos=%s player=%s boss=%s" % [
			_state, _player_captured, _current_anim_name, track_info, global_position,
			_player.global_position if _player != null and is_instance_valid(_player) else "null",
			_boss != null
		])

	match _state:
		HandState.APPEAR:
			_appear_elapsed += _dt
			# 备用捕获：在 Spine capture_check 事件未能触发时，用距离检测兜底
			if not _player_captured and not _fallback_capture_done and _appear_elapsed >= CAPTURE_FALLBACK_TIME:
				_fallback_capture_done = true
				if _try_capture_by_distance():
					print("[HELL_HAND_DEBUG] APPEAR: fallback distance capture SUCCESS")
					return
				else:
					print("[HELL_HAND_DEBUG] APPEAR: fallback distance capture MISS")
			# appear 动画播完且 capture_check 未捕获 → 收回消失
			if _is_current_anim_finished() and not _player_captured:
				print("[HELL_HAND_DEBUG] APPEAR: appear anim finished (polled), not captured → CLOSING")
				_state = HandState.CLOSING
				_play_anim(&"close", false)
		HandState.HOLD:
			# 禁锢时间到期 → 释放 + 收回
			if Time.get_ticks_msec() >= _imprison_end:
				print("[HELL_HAND_DEBUG] HOLD: stun expired → release + CLOSING")
				_release_player()
				_state = HandState.CLOSING
				_play_anim(&"close", false)
		HandState.CLOSING:
			# close 动画播完 → 清理并销毁
			if _is_current_anim_finished():
				print("[HELL_HAND_DEBUG] CLOSING: close anim finished (polled) → cleanup_and_free")
				_cleanup_and_free()


# ═══ ghostfist 击碎（蓝图：通过 HitArea.area_entered 信号）═══

func _on_ghostfist_hit(area: Area2D) -> void:
	if area == null:
		return
	if area.is_in_group("ghost_fist_hitbox"):
		print("[HELL_HAND_DEBUG] ghostfist_hit via HitArea: area=%s → release + CLOSING" % area.name)
		_release_player()
		_state = HandState.CLOSING
		_play_anim(&"close", false)


# 保留 MonsterBase 的 apply_hit 作为备用击碎路径
func apply_hit(hit: HitData) -> bool:
	if hit == null or hit.weapon_id != &"ghost_fist":
		return false
	print("[HELL_HAND_DEBUG] apply_hit: ghostfist → release + CLOSING")
	_release_player()
	_state = HandState.CLOSING
	_play_anim(&"close", false)
	return true


# ═══ 捕获/释放玩家 ═══

func _capture_player() -> void:
	_state = HandState.HOLD
	_player_captured = true
	_imprison_end = Time.get_ticks_msec() + int(_stun_time * 1000.0)
	_play_anim(&"hold", true)
	if _player != null and is_instance_valid(_player) and _player.has_method("set_external_control_frozen"):
		_player.call("set_external_control_frozen", true)
	if _boss != null and is_instance_valid(_boss):
		_boss._player_imprisoned = true
	print("[HELL_HAND_DEBUG] _capture_player: stun_time=%.2f imprison_end=%d" % [_stun_time, _imprison_end])


func _try_capture_by_distance() -> bool:
	## 备用捕获：纯距离检测，不依赖 Area2D 重叠
	if _player == null or not is_instance_valid(_player):
		return false
	var dist: float = global_position.distance_to(_player.global_position)
	print("[HELL_HAND_DEBUG] _try_capture_by_distance: dist=%.1f radius=%.1f hand_pos=%s player_pos=%s" % [dist, CAPTURE_FALLBACK_RADIUS, global_position, _player.global_position])
	if dist <= CAPTURE_FALLBACK_RADIUS:
		_capture_player()
		return true
	# 也尝试 Area2D 检测（可能此时已生效）
	if _is_player_in_capture_area():
		_capture_player()
		return true
	return false


func _is_player_in_capture_area() -> bool:
	if _capture_area == null:
		print("[HELL_HAND_DEBUG] _is_player_in_area: CaptureArea is NULL, cannot detect player")
		return false
	var bodies := _capture_area.get_overlapping_bodies()
	for body in bodies:
		if body != null and body.is_in_group("player"):
			print("[HELL_HAND_DEBUG] _is_player_in_area: found player in CaptureArea bodies=%d" % bodies.size())
			return true
	# 输出所有检测到的 body 名称用于调试
	var body_names: Array[String] = []
	for body in bodies:
		if body != null:
			body_names.append("%s(layer=%d)" % [body.name, body.collision_layer if "collision_layer" in body else -1])
	print("[HELL_HAND_DEBUG] _is_player_in_area: player NOT in CaptureArea bodies=%d names=%s player_pos=%s hand_pos=%s" % [bodies.size(), str(body_names), _player.global_position if _player != null and is_instance_valid(_player) else "null", global_position])
	return false


func _release_player() -> void:
	if _player_captured:
		print("[HELL_HAND_DEBUG] _release_player: unfreezing player")
	_player_captured = false
	if _player != null and is_instance_valid(_player) and _player.has_method("set_external_control_frozen"):
		_player.call("set_external_control_frozen", false)
	if _boss != null and is_instance_valid(_boss):
		_boss._player_imprisoned = false


func _cleanup_and_free() -> void:
	print("[HELL_HAND_DEBUG] _cleanup_and_free: releasing player and queue_free")
	_release_player()
	queue_free()


func _exit_tree() -> void:
	_release_player()


# ═══ 动画播放 + 轮询完成检测 ═══

func _play_anim(anim_name: StringName, loop: bool) -> void:
	_current_anim_name = anim_name
	_current_anim_loop = loop
	print("[HELL_HAND_DEBUG] _play_anim: name=%s loop=%s spine=%s pos=%s" % [anim_name, loop, _spine != null, global_position])
	if _spine == null:
		print("[HELL_HAND_DEBUG] _play_anim: spine is NULL, cannot play %s" % anim_name)
		return
	var anim_state: Object = _get_anim_state()
	if anim_state == null:
		print("[HELL_HAND_DEBUG] _play_anim: anim_state is NULL, cannot play %s" % anim_name)
		return
	if anim_state.has_method("set_animation"):
		anim_state.set_animation(String(anim_name), loop, 0)
		print("[HELL_HAND_DEBUG] _play_anim: set_animation('%s', %s, 0) called" % [anim_name, loop])
	elif anim_state.has_method("setAnimation"):
		anim_state.setAnimation(String(anim_name), loop, 0)
		print("[HELL_HAND_DEBUG] _play_anim: setAnimation('%s', %s, 0) called" % [anim_name, loop])
	else:
		print("[HELL_HAND_DEBUG] _play_anim: no set_animation/setAnimation method on anim_state!")


func _is_current_anim_finished() -> bool:
	## 轮询 SpineSprite 的 TrackEntry 判断当前动画是否播放完毕
	if _current_anim_loop:
		return false  # 循环动画永远不算"完成"
	if _spine == null:
		return true
	var anim_state: Object = _get_anim_state()
	if anim_state == null:
		return true
	var entry: Object = null
	if anim_state.has_method("get_current"):
		entry = anim_state.get_current(0)
	if entry == null:
		# 没有当前轨道条目 → 动画已经结束
		return true
	var done: bool = false
	if entry.has_method("is_complete"):
		done = entry.is_complete()
	elif entry.has_method("isComplete"):
		done = entry.isComplete()
	return done


func _get_anim_state() -> Object:
	if _spine == null:
		return null
	if _spine.has_method("get_animation_state"):
		return _spine.get_animation_state()
	elif _spine.has_method("getAnimationState"):
		return _spine.getAnimationState()
	return null


func _get_track_debug_info() -> String:
	## 获取当前轨道的调试信息（动画名、是否完成、循环时间等）
	var anim_state: Object = _get_anim_state()
	if anim_state == null:
		return "no_anim_state"
	var entry: Object = null
	if anim_state.has_method("get_current"):
		entry = anim_state.get_current(0)
	if entry == null:
		return "no_entry"
	var info := ""
	# 获取轨道当前动画名
	if entry.has_method("get_animation"):
		var anim: Object = entry.get_animation()
		if anim != null:
			if anim.has_method("get_name"):
				info += "anim=" + anim.get_name()
			elif anim.has_method("getName"):
				info += "anim=" + anim.getName()
	# 获取完成状态
	if entry.has_method("is_complete"):
		info += " complete=" + str(entry.is_complete())
	elif entry.has_method("isComplete"):
		info += " complete=" + str(entry.isComplete())
	# 获取循环状态
	if entry.has_method("get_loop"):
		info += " loop=" + str(entry.get_loop())
	elif entry.has_method("getLoop"):
		info += " loop=" + str(entry.getLoop())
	return info


func _list_children() -> String:
	var names: Array[String] = []
	for c in get_children():
		names.append(c.name)
	return str(names)


# ═══ Spine 事件名/动画名提取（与 GhostTug 同款）═══

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
