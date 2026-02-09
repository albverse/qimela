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
## 2. 使用 animation_ended（而非 completed）作为主信号
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

## API 签名: 1=(track,name,loop), 2=(name,loop,track)
var _api_signature: int = 2  # 默认官方签名


func setup(spine_sprite: Node) -> void:
	_spine_sprite = spine_sprite
	if _spine_sprite == null:
		push_error("[AnimDriverSpine] spine_sprite is null!")
		return

	var node_class: String = _spine_sprite.get_class()
	print("[AnimDriverSpine] Node class: %s" % node_class)

	if node_class != "SpineSprite":
		push_error("[AnimDriverSpine] Not SpineSprite!")
		return

	var anim_state = _spine_sprite.get_animation_state()
	if anim_state == null:
		push_error("[AnimDriverSpine] get_animation_state() returned null!")
		return

	_detect_api_signature(anim_state)
	_connect_signals()
	set_physics_process(true)
	print("[AnimDriverSpine] Setup complete, polling enabled")


func _detect_api_signature(anim_state: Object) -> void:
	## 按 TYPE 探测（更可靠）
	var methods: Array = anim_state.get_method_list()
	for m: Dictionary in methods:
		if m.get("name", "") != "set_animation":
			continue
		var args: Array = m.get("args", [])
		if args.size() < 3:
			continue

		var t0: int = int(args[0].get("type", -1))
		var t1: int = int(args[1].get("type", -1))
		var t2: int = int(args[2].get("type", -1))

		if t0 == TYPE_INT and t1 == TYPE_STRING:
			_api_signature = 1
			print("[AnimDriverSpine] Signature 1: (track, name, loop)")
			return
		if t0 == TYPE_STRING and t2 == TYPE_INT:
			_api_signature = 2
			print("[AnimDriverSpine] Signature 2: (name, loop, track) - OFFICIAL")
			return

	_api_signature = 2  # 默认官方
	print("[AnimDriverSpine] Using default signature 2")


func _connect_signals() -> void:
	## 优先 animation_ended（更接近"真正结束"）
	if _spine_sprite.has_signal("animation_ended"):
		_spine_sprite.animation_ended.connect(_on_animation_ended)
		print("[AnimDriverSpine] Connected animation_ended signal")
	elif _spine_sprite.has_signal("animation_completed"):
		_spine_sprite.animation_completed.connect(_on_animation_ended)
		print("[AnimDriverSpine] Connected animation_completed signal")
	else:
		push_warning("[AnimDriverSpine] No animation end signal, polling only")


func _physics_process(_delta: float) -> void:
	_poll_animation_completion()


func _poll_animation_completion() -> void:
	if _spine_sprite == null:
		return

	var anim_state = _spine_sprite.get_animation_state()
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


func _on_animation_ended(track_entry, _arg2 = null, _arg3 = null) -> void:
	## animation_ended 信号回调（可变参数以兼容不同版本）
	if track_entry == null:
		return

	var track_id: int = -1
	if track_entry.has_method("get_track_index"):
		track_id = track_entry.get_track_index()
	elif track_entry.has_method("getTrackIndex"):
		track_id = track_entry.getTrackIndex()

	if track_id < 0:
		return

	print("[AnimDriverSpine] signal ended: track=%d" % track_id)
	_on_track_completed(track_id, track_entry)


func _on_track_completed(track_id: int, track_entry) -> void:
	## 统一的完成处理
	if not _track_states.has(track_id):
		return

	var state: Dictionary = _track_states[track_id]
	if state.get("loop", false):
		return

	var anim_name: StringName = _get_animation_name(track_entry)
	print("[AnimDriverSpine] completed: track=%d name=%s" % [track_id, str(anim_name)])

	# track1 混出防止停最后一帧
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


func _play_animation(track: int, anim_name: StringName, loop: bool) -> void:
	var anim_str: String = String(anim_name)
	var anim_state = _spine_sprite.get_animation_state()
	if anim_state == null or not anim_state.has_method("set_animation"):
		push_error("[AnimDriverSpine] No set_animation!")
		return

	var _track_entry = null
	match _api_signature:
		1:
			_track_entry = anim_state.set_animation(track, anim_str, loop)
		2:
			_track_entry = anim_state.set_animation(anim_str, loop, track)
		_:
			_track_entry = anim_state.set_animation(anim_str, loop, track)

	_track_states[track] = {"anim": anim_name, "loop": loop}
	_completed_entry_id.erase(track)

	print("[AnimDriverSpine] play track=%d name=%s loop=%s" % [track, anim_str, loop])


func stop(track: int) -> void:
	if _spine_sprite == null:
		return
	if track == 1:
		_mix_out_track(track, track1_mix_out_duration)
	else:
		_clear_track(track)
	_track_states.erase(track)
	_completed_entry_id.erase(track)


func _mix_out_track(track: int, mix_duration: float) -> void:
	## 使用 set_empty_animation 混出（官方推荐）
	var anim_state = _spine_sprite.get_animation_state()
	if anim_state == null:
		return

	if anim_state.has_method("set_empty_animation"):
		anim_state.set_empty_animation(track, mix_duration)
	elif anim_state.has_method("setEmptyAnimation"):
		anim_state.setEmptyAnimation(track, mix_duration)
	else:
		_clear_track(track)

	print("[AnimDriverSpine] mix_out track=%d duration=%f" % [track, mix_duration])


func _clear_track(track: int) -> void:
	var anim_state = _spine_sprite.get_animation_state()
	if anim_state == null:
		return

	if anim_state.has_method("clear_track"):
		anim_state.clear_track(track)
	elif anim_state.has_method("clearTrack"):
		anim_state.clearTrack(track)


func _clear_all_tracks() -> void:
	var anim_state = _spine_sprite.get_animation_state()
	if anim_state == null:
		return

	if anim_state.has_method("clear_tracks"):
		anim_state.clear_tracks()
	elif anim_state.has_method("clearTracks"):
		anim_state.clearTracks()


## === 骨骼位置查询 ===

func get_bone_world_position(bone_name: String) -> Vector2:
	## 优先使用 get_global_bone_transform（Godot 空间，无需翻转）
	if _spine_sprite == null:
		return Vector2.ZERO

	if _spine_sprite.has_method("get_global_bone_transform"):
		var transform: Transform2D = _spine_sprite.get_global_bone_transform(bone_name)
		return transform.origin

	# 后备：传统 world_x/world_y 方式（需翻转 Y）
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

	# Spine Y 向上，Godot Y 向下 → 取负
	return Vector2(world_x, -world_y)
