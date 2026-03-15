extends Node2D
class_name HellHand

@export var imprison_sec: float = 3.0
var _player: Node2D = null

func setup(player: Node2D) -> void:
	_player = player
	if _player and _player.has_method("set"):
		_player.set("immobilized", true)

func _ready() -> void:
	await get_tree().create_timer(imprison_sec).timeout
	if _player and is_instance_valid(_player) and _player.has_method("set"):
		_player.set("immobilized", false)
	queue_free()

func apply_hit(hit: HitData) -> bool:
	if hit and hit.weapon_id == &"ghost_fist":
		if _player and is_instance_valid(_player) and _player.has_method("set"):
			_player.set("immobilized", false)
		queue_free()
		return true
	return false
