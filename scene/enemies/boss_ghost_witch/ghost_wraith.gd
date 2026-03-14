extends Node2D
class_name GhostWraith

@export var speed: float = 80.0

var _type: int = 1
var _player: Node2D = null
var _life: float = 10.0

func setup(wraith_type: int, player: Node2D, _spawn_pos: Vector2) -> void:
	_type = wraith_type
	_player = player

func _ready() -> void:
	$HitArea.area_entered.connect(_on_hit_area_entered)

func _physics_process(dt: float) -> void:
	_life -= dt
	if _life <= 0.0:
		queue_free()
		return
	if _player and is_instance_valid(_player):
		global_position.x += signf(_player.global_position.x - global_position.x) * speed * dt

func _on_hit_area_entered(area: Area2D) -> void:
	if area.is_in_group("ghost_fist_hitbox"):
		queue_free()
		return
	var p := area.get_parent()
	if p and p.is_in_group("player") and p.has_method("apply_damage"):
		p.call("apply_damage", 1, global_position)
		queue_free()
