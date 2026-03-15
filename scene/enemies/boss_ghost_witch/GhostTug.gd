extends Node2D
class_name GhostTug

@export var pull_speed: float = 400.0
var _player: Node2D
var _dying: bool = false

func _ready() -> void:
	add_to_group("ghost_tug")

func setup(player: Node2D) -> void:
	_player = player

func _physics_process(_dt: float) -> void:
	if _dying or _player == null:
		return
	if _player.has_method("set_external_control_frozen"):
		_player.call("set_external_control_frozen", true)
	if _player is CharacterBody2D:
		var body := _player as CharacterBody2D
		body.velocity.x = signf(global_position.x - _player.global_position.x) * pull_speed

func break_by_ghost_fist() -> void:
	_dying = true
	if _player and _player.has_method("set_external_control_frozen"):
		_player.call("set_external_control_frozen", false)
	queue_free()
