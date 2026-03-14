extends Node2D
class_name GhostTug

var _player: Node2D = null
var _boss: Node2D = null
var _pull_speed: float = 400.0

func setup(player: Node2D, boss: Node2D, pull_speed: float) -> void:
	_player = player
	_boss = boss
	_pull_speed = pull_speed

func _ready() -> void:
	var hit_area: Area2D = $HitArea
	hit_area.area_entered.connect(_on_hit)

func _physics_process(_dt: float) -> void:
	_pull_player_toward_boss()

func _pull_player_toward_boss() -> void:
	if _player == null or _boss == null:
		return
	if not is_instance_valid(_player) or not is_instance_valid(_boss):
		return
	var dir_x := signf(_boss.global_position.x - _player.global_position.x)
	if _player.has_method("set_external_control_frozen"):
		_player.call("set_external_control_frozen", true)
	if _player.has_method("set"):
		_player.set("velocity", Vector2(dir_x * _pull_speed, _player.get("velocity").y if _player.get("velocity") != null else 0.0))

func _on_hit(area: Area2D) -> void:
	if area.is_in_group("ghost_fist_hitbox"):
		queue_free()

func _exit_tree() -> void:
	if _player and is_instance_valid(_player) and _player.has_method("set_external_control_frozen"):
		_player.call("set_external_control_frozen", false)
