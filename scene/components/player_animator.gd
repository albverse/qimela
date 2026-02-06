extends Node
class_name PlayerAnimator

enum AnimPriority {
	IDLE = 0,
	CHAIN = 1,
	JUMP_DOWN = 1,
	MOVE = 2,
	JUMP = 3,
	HURT = 8,
	DIE = 10
}

@export_group("基础动画")
@export var anim_idle: StringName = &"idle"
@export var anim_walk: StringName = &"walk"
@export var anim_run: StringName = &"run"

@export_group("跳跃动画")
@export var anim_jump_up: StringName = &"jump_up"
@export var anim_jump_loop: StringName = &"jump_loop"
@export var anim_jump_down: StringName = &"jump_down"

@export_group("受伤与死亡")
@export var anim_hurt: StringName = &"hurt"
@export var anim_die: StringName = &"die"

@export_group("锁链动画 - 发射")
@export var anim_chain_r: StringName = &"chain_R"
@export var anim_chain_l: StringName = &"chain_L"
@export var anim_chain_lr: StringName = &"chain_LR"

@export_group("锁链动画 - 取消")
@export var anim_chain_r_cancel: StringName = &"chain_R_cancel"
@export var anim_chain_l_cancel: StringName = &"chain_L_cancel"
@export var anim_chain_lr_cancel: StringName = &"chain_LR_cancel"

@export_group("Spine节点配置")
@export var spine_path: NodePath = ^"../Visual/SpineSprite"

@export_group("骨骼锚点名称")
@export var bone_chain_anchor_l: StringName = &"chain_anchor_l"
@export var bone_chain_anchor_r: StringName = &"chain_anchor_r"

@export_group("一次性动画回收")
@export var one_shot_fallback_timeout: float = 1.2

var _player: Player = null
var _spine: Node = null
var _current_anim: StringName = &""
var _current_priority: int = 0
var _current_track: int = 0
var _is_one_shot_playing: bool = false
var _one_shot_timer: float = 0.0
var _has_completion_signal: bool = false
var _return_anim: StringName = &""

func _ready() -> void:
	_player = _find_player()
	if _player == null:
		push_error("[PlayerAnimator] Player not found.")
		return
	
	_spine = get_node_or_null(spine_path)
	if _spine == null:
		push_error("[PlayerAnimator] SpineSprite not found at: %s" % spine_path)
	else:
		if _spine.has_signal("animation_completed"):
			_spine.connect("animation_completed", _on_animation_completed)
			_has_completion_signal = true
		elif _spine.has_signal("animation_complete"):
			_spine.connect("animation_complete", _on_animation_completed)
			_has_completion_signal = true
	
	play_idle()
	set_process(true)

func _process(delta: float) -> void:
	if _has_completion_signal:
		return
	if not _is_one_shot_playing:
		return
	if _one_shot_timer <= 0.0:
		return
	_one_shot_timer -= delta
	if _one_shot_timer <= 0.0:
		_finish_one_shot()

func _find_player() -> Player:
	var p: Node = self
	while p != null and not (p is Player):
		p = p.get_parent()
	return p as Player

func _get_anim_priority(anim_name: StringName) -> int:
	if anim_name == anim_die:
		return AnimPriority.DIE
	if anim_name == anim_hurt:
		return AnimPriority.HURT
	if anim_name == anim_jump_up or anim_name == anim_jump_loop:
		return AnimPriority.JUMP
	if anim_name == anim_walk or anim_name == anim_run:
		return AnimPriority.MOVE
	if anim_name == anim_jump_down:
		return AnimPriority.JUMP_DOWN
	if anim_name in [anim_chain_r, anim_chain_l, anim_chain_lr, anim_chain_r_cancel, anim_chain_l_cancel, anim_chain_lr_cancel]:
		return AnimPriority.CHAIN
	return AnimPriority.IDLE

func _can_interrupt(new_anim: StringName) -> bool:
	var new_priority := _get_anim_priority(new_anim)
	if _current_anim == anim_jump_up or _current_anim == anim_jump_loop:
		return new_priority >= AnimPriority.HURT
	return new_priority >= _current_priority

func _play(anim_name: StringName, loop: bool = true, track: int = 0, return_to_idle: bool = false, force: bool = false) -> void:
	if _spine == null:
		return
	
	if anim_name == StringName("") or anim_name == &"":
		return
	
	var anim_name_str := String(anim_name)
	if anim_name_str.is_empty():
		return
	
	if loop and anim_name == _current_anim and track == _current_track:
		return
	
	if not force and _current_anim != &"":
		if not _can_interrupt(anim_name):
			return
	
	_current_anim = anim_name
	_current_priority = _get_anim_priority(anim_name)
	_current_track = track
	_is_one_shot_playing = not loop
	_one_shot_timer = one_shot_fallback_timeout if (not loop and not _has_completion_signal) else 0.0
	_return_anim = anim_idle if return_to_idle else &""
	
	if not _spine.has_method("get_animation_state"):
		return
	
	var anim_state: Object = _spine.call("get_animation_state")
	if anim_state == null:
		return
	
	if anim_state.has_method("set_animation"):
		anim_state.set_animation(anim_name_str, loop, track)

func _on_animation_completed(_a = null, _b = null, _c = null) -> void:
	_finish_one_shot()

func _finish_one_shot() -> void:
	if not _is_one_shot_playing and _return_anim == &"":
		return
	
	_is_one_shot_playing = false
	_one_shot_timer = 0.0
	
	if _return_anim != &"":
		var return_to := _return_anim
		_return_anim = &""
		_play(return_to, true, 0, false)

func play_idle(force: bool = false) -> void:
	_play(anim_idle, true, 0, false, force)

func play_walk(force: bool = false) -> void:
	_play(anim_walk, true, 0, false, force)

func play_run(force: bool = false) -> void:
	_play(anim_run, true, 0, false, force)

func play_jump_up() -> void:
	_return_anim = anim_jump_loop
	_play(anim_jump_up, false)

func play_jump_loop() -> void:
	_play(anim_jump_loop, true)

func play_jump_down() -> void:
	_play(anim_jump_down, false, 0, false, true)

func play_hurt() -> void:
	_return_anim = anim_idle
	_play(anim_hurt, false, 0, false, true)

func play_die() -> void:
	_return_anim = &""
	_play(anim_die, false, 0, false, true)

func play_chain_fire(slot: int) -> void:
	if slot == 0:
		_play(anim_chain_r, false, 0, true)
	else:
		_play(anim_chain_l, false, 0, true)

func play_chain_cancel(right_active: bool, left_active: bool) -> void:
	if right_active and left_active:
		_play(anim_chain_lr_cancel, false, 0, true)
	elif right_active:
		_play(anim_chain_r_cancel, false, 0, true)
	elif left_active:
		_play(anim_chain_l_cancel, false, 0, true)

func get_chain_anchor_position(use_right_hand: bool) -> Vector2:
	if _spine == null or _player == null:
		return _get_fallback_hand_position(use_right_hand)
	
	var bone_name: StringName = bone_chain_anchor_r if use_right_hand else bone_chain_anchor_l
	
	if _spine.has_method("get_skeleton"):
		var skeleton: Object = _spine.call("get_skeleton")
		if skeleton != null and skeleton.has_method("find_bone"):
			var bone: Object = skeleton.call("find_bone", String(bone_name))
			if bone != null and bone.has_method("get_world_x") and bone.has_method("get_world_y"):
				var local_x: float = bone.call("get_world_x")
				var local_y: float = bone.call("get_world_y")
				var spine_node := _spine as Node2D
				if spine_node != null:
					return spine_node.to_global(Vector2(local_x, local_y))
	
	return _get_fallback_hand_position(use_right_hand)

func _get_fallback_hand_position(use_right_hand: bool) -> Vector2:
	if _player == null:
		return Vector2.ZERO
	var hand_path := _player.hand_r_path if use_right_hand else _player.hand_l_path
	var hand: Node2D = _player.get_node_or_null(hand_path) as Node2D
	if hand != null:
		return hand.global_position
	return _player.global_position

func get_current_anim() -> StringName:
	return _current_anim

func is_one_shot_playing() -> bool:
	return _is_one_shot_playing

func is_playing(anim_name: StringName) -> bool:
	return _current_anim == anim_name

func has_spine() -> bool:
	return _spine != null
