extends Node
class_name AnimDriverSpine

## Spine 动画驱动器（2026-02-08 官方标准版）
##
## DOC_CHECK: spine-godot Runtime Documentation 已核对（2026-02-08）
## 官方签名：set_animation(animation_name, loop, track)
## 核心策略：信号 + 轮询双保险
##
## 关键修正：
## 1. 按 TYPE 探测签名（不依赖参数名）
## 2. 使用 animation_completed 作为主信号（ended/interrupted 仅用于观测）
## 3. 轮询不持有 TE，只记录 instance_id 去重
## 4. 骨骼坐标优先用 get_global_bone_transform

signal anim_completed(track: int, anim_name: StringName)

enum PlayMode {
	OVERLAY,
	EXCLUSIVE,
	REPLACE_TRACK
}

var _spine_sprite: Node = null
var _track_states: Dictionary = {}  # track_id -> {anim:String, loop:bool}
var _completed_entry_id: Dictionary = {}  # track_id -> int

var default_mix_duration: float = 0.1
var track1_mix_out_duration: float = 0.08

## 调试开关：设为true打印详细日志
var debug_log: bool = false

## API 签名: 1=(track,name,loop), 2=(name,loop,track)
var _api_signature: int = 2  # 默认官方签名
var _manual_update_mode: bool = false


func setup(spine_sprite: Node) -> void:
	_spine_sprite = spine_sprite
	if _spine_sprite == null:
		push_error("[AnimDriverSpine] spine_sprite is null!")
		return

	var node_class: String = _spine_sprite.get_class()
	if debug_log: print("[AnimDriverSpine] Node class: %s" % node_class)

	if node_class != "SpineSprite":
		push_error("[AnimDriverSpine] Not SpineSprite!")
		return

	var anim_state = _get_animation_state()
	if anim_state == null:
		push_error("[AnimDriverSpine] get_animation_state()/getAnimationState() returned null!")
		return

	_detect_api_signature(anim_state)
	_connect_signals()
	_check_update_mode()
	set_physics_process(true)
	if debug_log: print("[AnimDriverSpine] Setup complete, polling enabled")


func _get_animation_state():
	if _spine_sprite == null:
		return null
	if _spine_sprite.has_method("get_animation_state"):
		return _spine_sprite.get_animation_state()
	if _spine_sprite.has_method("getAnimationState"):
		return _spine_sprite.getAnimationState()
	return null


func _detect_api_signature(anim_state: Object) -> void:
	## 按 TYPE 探测（更可靠）
	var methods: Array = anim_state.get_method_list()
	for m: Dictionary in methods:
		var method_name: String = m.get("name", "")
		if method_name != "set_animation" and method_name != "setAnimation":
			continue
		var args: Array = m.get("args", [])
		if args.size() < 3:
			continue

		var t0: int = int(args[0].get("type", -1))
		var t1: int = int(args[1].get("type", -1))
		var t2: int = int(args[2].get("type", -1))

		if t0 == TYPE_INT and t1 == TYPE_STRING and t2 == TYPE_BOOL:
			_api_signature = 1
			if debug_log: print("[AnimDriverSpine] Signature 1: (track, name, loop)")
			return
		if t0 == TYPE_STRING and t1 == TYPE_BOOL and t2 == TYPE_INT:
			_api_signature = 2
			if debug_log: print("[AnimDriverSpine] Signature 2: (name, loop, track) - OFFICIAL")
			return

	_api_signature = 2  # 默认官方
	if debug_log: print("[AnimDriverSpine] Using default signature 2")


func _connect_signals() -> void:
	## 主信号：animation_completed（自然完成）
	## 观测信号：animation_ended / animation_interrupted（日志与排障）
	if _spine_sprite.has_signal("animation_completed"):
		_spine_sprite.animation_completed.connect(_on_animation_completed)
		if debug_log: print("[AnimDriverSpine] Connected animation_completed signal (preferred)")
	elif _spine_sprite.has_signal("animation_ended"):
		_spine_sprite.animation_ended.connect(_on_animation_completed)
		if debug_log: print("[AnimDriverSpine] Connected animation_ended signal (fallback)")
	else:
		push_warning("[AnimDriverSpine] No animation end signal, polling only")

	if _spine_sprite.has_signal("animation_ended"):
		_spine_sprite.animation_ended.connect(_on_animation_ended_observe)
	if _spine_sprite.has_signal("animation_interrupted"):
		_spine_sprite.animation_interrupted.connect(_on_animation_interrupted_observe)


func _physics_process(_delta: float) -> void:
	_update_manual_skeleton_if_needed()
	_poll_animation_completion()


func _check_update_mode() -> void:
	_manual_update_mode = false
	if _spine_sprite == null:
		return

	var mode: Variant = null
	if _spine_sprite.has_method("get_update_mode"):
		mode = _spine_sprite.get_update_mode()
	elif _spine_sprite.has_method("getUpdateMode"):
		mode = _spine_sprite.getUpdateMode()

	if mode == null:
		return

	if mode is String:
		_manual_update_mode = String(mode).to_lower().find("manual") >= 0
	elif mode is int:
		# 常见枚举: 0=Process, 1=Physics, 2=Manual
		_manual_update_mode = int(mode) == 2

	if _manual_update_mode:
		if debug_log: print("[AnimDriverSpine] Update mode=Manual, will call update_skeleton each physics frame")


func _update_manual_skeleton_if_needed() -> void:
	if not _manual_update_mode or _spine_sprite == null:
		return

	if _spine_sprite.has_method("update_skeleton"):
		_spine_sprite.update_skeleton()
	elif _spine_sprite.has_method("updateSkeleton"):
		_spine_sprite.updateSkeleton()
	else:
		push_warning("[AnimDriverSpine] Manual mode detected but no update_skeleton()/updateSkeleton() method")


func _poll_animation_completion() -> void:
	if _spine_sprite == null:
		return

	var anim_state = _get_animation_state()
	if anim_state == null:
		return

	for track_id in _track_states.keys():
		var state: Dictionary = _track_states[track_id]
		if state.get("loop", false):
			continue  # 循环动画不检测

		var entry = null
		if anim_state.has_method("get_current"):
			entry = anim_state.get_current(track_id)
		elif anim_state.has_method("getCurrent"):
			entry = anim_state.getCurrent(track_id)

		if entry == null:
			continue

		var done: bool = false
		if entry.has_method("is_complete"):
			done = entry.is_complete()
		elif entry.has_method("isComplete"):
			done = entry.isComplete()

		if not done:
			continue

		var eid: int = entry.get_instance_id()
		if _completed_entry_id.get(track_id, -1) == eid:
			continue

		_completed_entry_id[track_id] = eid
		_on_track_completed(track_id, entry)




func _extract_track_entry(sig_a, sig_b = null, sig_c = null):
	# 官方较新签名常见为 (sprite, track_entry[, loop_count])；旧版可能直接传 track_entry。
	# 按能力判断，拿到真正的 SpineTrackEntry。
	var candidates: Array = [sig_a, sig_b, sig_c]
	for c in candidates:
		if c == null:
			continue
		if c.has_method("get_track_index") or c.has_method("getTrackIndex"):
			return c
	return null


func _on_animation_completed(track_entry, _arg2 = null, _arg3 = null) -> void:
	## 动画完成信号回调（可变参数以兼容不同版本）
	var entry = _extract_track_entry(track_entry, _arg2, _arg3)
	if entry == null:
		if debug_log: print("[AnimDriverSpine] animation_completed ignored: no track_entry in args")
		return

	var track_id: int = -1
	if entry.has_method("get_track_index"):
		track_id = entry.get_track_index()
	elif entry.has_method("getTrackIndex"):
		track_id = entry.getTrackIndex()

	if track_id < 0:
		return

	# === P1 FIX: 验证信号对应的动画是否与当前追踪的动画一致 ===
	if _track_states.has(track_id):
		var expected_anim: StringName = _track_states[track_id].get("anim", &"")
		var signal_anim: StringName = _get_animation_name(entry)
		if signal_anim != &"" and signal_anim != expected_anim:
			if debug_log: print("[AnimDriverSpine] signal IGNORED: track=%d got=%s expected=%s (stale/replaced)" % [track_id, signal_anim, expected_anim])
			return

	if debug_log: print("[AnimDriverSpine] signal completed: track=%d" % track_id)
	_on_track_completed(track_id, entry)


func _on_animation_ended_observe(track_entry, _arg2 = null, _arg3 = null) -> void:
	var entry = _extract_track_entry(track_entry, _arg2, _arg3)
	if entry == null:
		return
	var track_id: int = -1
	if entry.has_method("get_track_index"):
		track_id = entry.get_track_index()
	elif entry.has_method("getTrackIndex"):
		track_id = entry.getTrackIndex()
	if debug_log: print("[AnimDriverSpine] signal observed: animation_ended track=%d" % track_id)


func _on_animation_interrupted_observe(track_entry, _arg2 = null, _arg3 = null) -> void:
	var entry = _extract_track_entry(track_entry, _arg2, _arg3)
	if entry == null:
		return
	var track_id: int = -1
	if entry.has_method("get_track_index"):
		track_id = entry.get_track_index()
	elif entry.has_method("getTrackIndex"):
		track_id = entry.getTrackIndex()
	if debug_log: print("[AnimDriverSpine] signal observed: animation_interrupted track=%d" % track_id)


func _on_track_completed(track_id: int, track_entry) -> void:
	if not _track_states.has(track_id):
		return

	var state: Dictionary = _track_states[track_id]
	if state.get("loop", false):
		return

	var anim_name: StringName = _get_animation_name(track_entry)
	if debug_log: print("[AnimDriverSpine] completed: track=%d name=%s" % [track_id, str(anim_name)])

	if track_id == 1:
		_mix_out_track(1, track1_mix_out_duration)

	_track_states.erase(track_id)
	_completed_entry_id.erase(track_id)
	anim_completed.emit(track_id, anim_name)


func _get_animation_name(entry) -> StringName:
	if entry == null:
		return &""

	var anim = null
	if entry.has_method("get_animation"):
		anim = entry.get_animation()
	elif entry.has_method("getAnimation"):
		anim = entry.getAnimation()

	if anim == null:
		return &""

	var anim_name_str: String = ""
	if anim.has_method("get_name"):
		anim_name_str = anim.get_name()
	elif anim.has_method("getName"):
		anim_name_str = anim.getName()

	return StringName(anim_name_str)


## === 播放 API ===

func play(track: int, anim_name: StringName, loop: bool, mode: int = PlayMode.OVERLAY) -> void:
	if _spine_sprite == null:
		return

	match mode:
		PlayMode.OVERLAY:
			_play_animation(track, anim_name, loop)
		PlayMode.EXCLUSIVE:
			_clear_all_tracks()
			_play_animation(track, anim_name, loop)
		PlayMode.REPLACE_TRACK:
			_clear_track(track)
			_play_animation(track, anim_name, loop)


func queue(track: int, anim_name: StringName, delay: float, loop: bool) -> void:
	if _spine_sprite == null:
		return
	var anim_state = _get_animation_state()
	if anim_state == null:
		return

	var anim_str: String = String(anim_name)
	if anim_state.has_method("add_animation"):
		anim_state.add_animation(anim_str, delay, loop, track)
	elif anim_state.has_method("addAnimation"):
		anim_state.addAnimation(anim_str, delay, loop, track)
	else:
		# 兼容旧实现：缺失 add_animation 时退化为直接播放
		_play_animation(track, anim_name, loop)
		return

	_track_states[track] = {"anim": anim_name, "loop": loop}
	_completed_entry_id.erase(track)


func _play_animation(track: int, anim_name: StringName, loop: bool) -> void:
	var anim_str: String = String(anim_name)
	var anim_state = _get_animation_state()
	if anim_state == null:
		push_error("[AnimDriverSpine] No animation state!")
		return

	var _track_entry = null
	if anim_state.has_method("set_animation"):
		match _api_signature:
			1:
				_track_entry = anim_state.set_animation(track, anim_str, loop)
			2:
				_track_entry = anim_state.set_animation(anim_str, loop, track)
			_:
				_track_entry = anim_state.set_animation(anim_str, loop, track)
	elif anim_state.has_method("setAnimation"):
		match _api_signature:
			1:
				_track_entry = anim_state.setAnimation(track, anim_str, loop)
			2:
				_track_entry = anim_state.setAnimation(anim_str, loop, track)
			_:
				_track_entry = anim_state.setAnimation(anim_str, loop, track)
	else:
		push_error("[AnimDriverSpine] No set_animation/setAnimation!")
		return

	_track_states[track] = {"anim": anim_name, "loop": loop}
	_completed_entry_id.erase(track)

	if debug_log: print("[AnimDriverSpine] play track=%d name=%s loop=%s" % [track, anim_str, loop])


func stop(track: int) -> void:
	if _spine_sprite == null:
		return
	if track == 1:
		_mix_out_track(track, track1_mix_out_duration)
	else:
		_clear_track(track)
	_track_states.erase(track)
	_completed_entry_id.erase(track)


func stop_all() -> void:
	_clear_all_tracks()
	_track_states.clear()
	_completed_entry_id.clear()


func _mix_out_track(track: int, mix_duration: float) -> void:
	var anim_state = _get_animation_state()
	if anim_state == null:
		return

	if anim_state.has_method("set_empty_animation"):
		anim_state.set_empty_animation(track, mix_duration)
	elif anim_state.has_method("setEmptyAnimation"):
		anim_state.setEmptyAnimation(track, mix_duration)
	else:
		_clear_track(track)

	if debug_log: print("[AnimDriverSpine] mix_out track=%d duration=%f" % [track, mix_duration])


func _clear_track(track: int) -> void:
	var anim_state = _get_animation_state()
	if anim_state == null:
		return

	if anim_state.has_method("clear_track"):
		anim_state.clear_track(track)
	elif anim_state.has_method("clearTrack"):
		anim_state.clearTrack(track)


func _clear_all_tracks() -> void:
	var anim_state = _get_animation_state()
	if anim_state == null:
		return

	if anim_state.has_method("clear_tracks"):
		anim_state.clear_tracks()
	elif anim_state.has_method("clearTracks"):
		anim_state.clearTracks()


## === 查询 API ===

func get_current_anim(track: int) -> StringName:
	if _track_states.has(track):
		return _track_states[track].get("anim", &"")
	return &""


## === 骨骼位置查询 ===

func get_bone_world_position(bone_name: String) -> Vector2:
	if _spine_sprite == null:
		return Vector2.ZERO

	if _spine_sprite.has_method("get_global_bone_transform"):
		var transform: Transform2D = _spine_sprite.get_global_bone_transform(bone_name)
		return transform.origin

	var skeleton = null
	if _spine_sprite.has_method("get_skeleton"):
		skeleton = _spine_sprite.get_skeleton()
	elif _spine_sprite.has_method("getSkeleton"):
		skeleton = _spine_sprite.getSkeleton()

	if skeleton == null:
		return Vector2.ZERO

	var bone = null
	if skeleton.has_method("find_bone"):
		bone = skeleton.find_bone(bone_name)
	elif skeleton.has_method("findBone"):
		bone = skeleton.findBone(bone_name)

	if bone == null:
		push_warning("[AnimDriverSpine] Bone not found: '%s'" % bone_name)
		return Vector2.ZERO

	var world_x: float = 0.0
	var world_y: float = 0.0

	if bone.has_method("get_world_x"):
		world_x = bone.get_world_x()
	elif bone.has_method("getWorldX"):
		world_x = bone.getWorldX()

	if bone.has_method("get_world_y"):
		world_y = bone.get_world_y()
	elif bone.has_method("getWorldY"):
		world_y = bone.getWorldY()

	# Fallback 与 Ghost Fist 路径保持一致：
	# bone.get_world_x/y() 作为 SpineSprite 局部坐标，再通过 to_global 转到 Godot 全局坐标。
	# 不做手动 Y 取反，避免不同运行时下出现双重翻转。
	return _spine_sprite.to_global(Vector2(world_x, world_y))
