extends MonsterBase
class_name GhostTug

@export var pull_speed: float = 400.0
var _player: Node2D = null
var _dying: bool = false

func _ready() -> void:
	species_id = &"ghost_tug"
	has_hp = false
	super._ready()
	add_to_group("ghost_tug")

func setup(player: Node2D) -> void:
	_player = player

func apply_hit(hit: HitData) -> bool:
	if _dying:
		return false
	if hit == null or hit.weapon_id != &"ghost_fist":
		return false
	_dying = true
	if _player != null and _player.has_method("set_external_control_frozen"):
		_player.call("set_external_control_frozen", false)
	queue_free()
	return true

func _physics_process(_dt: float) -> void:
	if _dying or _player == null:
		return
	if _player.has_method("set_external_control_frozen"):
		_player.call("set_external_control_frozen", true)
	if "velocity" in _player:
		_player.velocity.x = signf(global_position.x - _player.global_position.x) * pull_speed
