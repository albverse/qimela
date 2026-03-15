extends MonsterBase
class_name HellHand

enum HandState { APPEAR, HOLD, CLOSING }

var _state: int = HandState.APPEAR
var _player: Node2D
var _boss: BossGhostWitch
var _imprison_end: int = 0
var _stun_time: float = 3.0

func _ready() -> void:
	species_id = &"hell_hand"
	has_hp = false
	super._ready()
	add_to_group("hell_hand")

func setup(player: Node2D, boss: BossGhostWitch, stun_time: float) -> void:
	_player = player
	_boss = boss
	_stun_time = stun_time
	_on_spine_event("capture_check")

func _on_spine_event(a1 = null, a2 = null, a3 = null, a4 = null) -> void:
	var event_name := &""
	for v in [a4, a3, a2, a1]:
		if v is StringName and v != &"":
			event_name = v
			break
		if v is String and v != "":
			event_name = StringName(v)
			break
	if event_name != &"capture_check":
		return
	if _is_player_in_capture_area():
		_capture_player()
	else:
		_state = HandState.CLOSING

func _capture_player() -> void:
	_state = HandState.HOLD
	_imprison_end = Time.get_ticks_msec() + int(_stun_time * 1000.0)
	if _player != null and _player.has_method("set_external_control_frozen"):
		_player.call("set_external_control_frozen", true)
	if _boss != null:
		_boss._player_imprisoned = true

func _physics_process(_dt: float) -> void:
	if _state == HandState.HOLD and Time.get_ticks_msec() >= _imprison_end:
		_release_player()
		_state = HandState.CLOSING
	if _state == HandState.CLOSING:
		_release_player()
		queue_free()

func apply_hit(hit: HitData) -> bool:
	if hit == null or hit.weapon_id != &"ghost_fist":
		return false
	_release_player()
	_state = HandState.CLOSING
	return true

func _is_player_in_capture_area() -> bool:
	return _player != null and global_position.distance_to(_player.global_position) < 64.0

func _release_player() -> void:
	if _player != null and _player.has_method("set_external_control_frozen"):
		_player.call("set_external_control_frozen", false)
	if _boss != null:
		_boss._player_imprisoned = false
