extends Node2D
class_name WitchScythe
@export var speed: float = 260.0
var _owner: BossGhostWitch
func bind_owner(owner: BossGhostWitch) -> void:
	_owner = owner
func _ready() -> void:
	add_to_group("witch_scythe")
func _physics_process(delta: float) -> void:
	if _owner == null or not is_instance_valid(_owner):
		queue_free()
		return
	if _owner._scythe_recall_requested:
		var d := (_owner.global_position - global_position).normalized()
		global_position += d * speed * delta
		if global_position.distance_to(_owner.global_position) < 16.0:
			_owner.recall_scythe()
			queue_free()
	else:
		global_position.x += signf(_owner.scale.x) * speed * delta
