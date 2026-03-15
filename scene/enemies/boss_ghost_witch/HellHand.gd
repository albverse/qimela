extends Node2D
class_name HellHand

enum HandState { APPEAR, HOLD, CLOSING }

var _boss: BossGhostWitch
var _player: Node2D
var _state: int = HandState.APPEAR
var _imprison_end: int = 0
var _stun_time: float = 3.0

func _ready() -> void:
	add_to_group("hell_hand")

func setup(boss: BossGhostWitch, player: Node2D, _escape_time: float, stun_time: float) -> void:
	_boss = boss
	_player = player
	_stun_time = stun_time
	_capture_player()

func _capture_player() -> void:
	if _player == null:
		queue_free()
		return
	_state = HandState.HOLD
	_imprison_end = Time.get_ticks_msec() + int(_stun_time * 1000.0)
	if _player.has_method("set_external_control_frozen"):
		_player.call("set_external_control_frozen", true)
	if _boss:
		_boss._player_imprisoned = true

func _release_player() -> void:
	if _player and _player.has_method("set_external_control_frozen"):
		_player.call("set_external_control_frozen", false)
	if _boss:
		_boss._player_imprisoned = false

func _physics_process(_dt: float) -> void:
	if _state == HandState.HOLD and Time.get_ticks_msec() >= _imprison_end:
		_release_player()
		_state = HandState.CLOSING
		queue_free()

func _exit_tree() -> void:
	_release_player()
