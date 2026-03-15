extends Area2D
class_name GhostSummon

var _life: float = 3.0

func _ready() -> void:
	add_to_group("ghost_summon")
	body_entered.connect(_on_body_entered)

func _physics_process(dt: float) -> void:
	_life -= dt
	if _life <= 0.0:
		queue_free()

func _on_body_entered(body: Node) -> void:
	if body and body.is_in_group("player") and body.has_method("apply_damage"):
		body.call("apply_damage", 1, global_position)
