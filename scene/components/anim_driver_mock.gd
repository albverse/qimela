extends Node
class_name AnimDriverMock

## Phase0 占位动画驱动器
## loop=true 的动画永不触发 anim_completed
## loop=false 在倒计时结束后触发 anim_completed(track, anim_name)

signal anim_completed(track: int, anim_name: StringName)

# 写死时长表（Phase0 用；Phase1 由 Spine 真实时长替代）
var _durations: Dictionary = {
	# Chain 模式 locomotion
	&"chain_/idle": 1.0,
	&"chain_/walk": 0.6,
	&"chain_/run": 0.4,
	&"chain_/jump_up": 0.3,
	&"chain_/jump_loop": 0.5,
	&"chain_/jump_down": 0.3,
	# Chain 模式 action
	&"chain_/chain_R": 0.4,
	&"chain_/chain_L": 0.4,
	&"chain_/anim_chain_cancel_R": 0.3,
	&"chain_/anim_chain_cancel_L": 0.3,
	&"chain_/fuse_progress": 0.6,
	&"chain_/fuse_hurt": 0.35,
	&"chain_/hurt": 0.35,
	&"chain_/die": 1.0,
	&"chain_/sword_light_idle": 0.4,
	&"chain_/sword_light_move": 0.4,
	&"chain_/sword_light_air": 0.35,
	&"chain_/knife_light_idle": 0.35,
	&"chain_/knife_light_move": 0.35,
	&"chain_/knife_light_air": 0.3,
	# Ghost Fist 模式 locomotion
	&"ghost_fist_/idle": 1.0,
	&"ghost_fist_/walk": 0.6,
	&"ghost_fist_/run": 0.4,
	&"ghost_fist_/jump_up": 0.3,
	&"ghost_fist_/jump_loop": 0.5,
	&"ghost_fist_/jump_down": 0.3,
	# Ghost Fist 模式 action
	&"ghost_fist_/attack_1": 0.5,
	&"ghost_fist_/attack_2": 0.5,
	&"ghost_fist_/attack_3": 0.5,
	&"ghost_fist_/attack_4": 0.6,
	&"ghost_fist_/cooldown": 0.5,
	&"ghost_fist_/enter": 0.4,
	&"ghost_fist_/exit": 0.4,
	&"ghost_fist_/hurt": 0.35,
	&"ghost_fist_/die": 1.0,
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
