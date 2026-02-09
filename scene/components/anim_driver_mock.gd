extends Node
class_name AnimDriverMock

## Phase0 占位动画驱动器
## loop=true 的动画永不触发 anim_completed
## loop=false 在倒计时结束后触发 anim_completed(track, anim_name)

signal anim_completed(track: int, anim_name: StringName)

# 写死时长表（Phase0 用；Phase1 由 Spine 真实时长替代）
var _durations: Dictionary = {
	&"idle": 1.0,
	&"walk": 0.6,
	&"run": 0.4,
	&"jump_up": 0.3,
	&"jump_loop": 0.5,
	&"jump_down": 0.3,
	&"chain_R": 0.4,
	&"chain_L": 0.4,
	&"anim_chain_cancel_R": 0.3,
	&"anim_chain_cancel_L": 0.3,
	&"fuse_progress": 0.6,
	&"fuse_hurt": 0.35,
	&"hurt": 0.35,
	&"die": 1.0,
	&"sword_light_idle": 0.4,
	&"sword_light_move": 0.4,
	&"sword_light_air": 0.35,
	&"knife_light_idle": 0.35,
	&"knife_light_move": 0.35,
	&"knife_light_air": 0.3,
}

# 每条 track: {anim: StringName, loop: bool, remaining: float}
var _tracks: Dictionary = {}


func play(track: int, anim_name: StringName, loop: bool) -> void:
	var dur: float = _durations.get(anim_name, 0.5)
	_tracks[track] = {"anim": anim_name, "loop": loop, "remaining": dur}


func stop(track: int) -> void:
	_tracks.erase(track)


func get_current_anim(track: int) -> StringName:
	if _tracks.has(track):
		return _tracks[track]["anim"]
	return &""


func tick(dt: float) -> void:
	var finished: Array = []
	for track_id: int in _tracks:
		var data: Dictionary = _tracks[track_id]
		if data["loop"]:
			continue
		data["remaining"] -= dt
		if data["remaining"] <= 0.0:
			finished.append({"track": track_id, "anim": data["anim"]})

	for f: Dictionary in finished:
		_tracks.erase(f["track"])
		anim_completed.emit(f["track"], f["anim"])
