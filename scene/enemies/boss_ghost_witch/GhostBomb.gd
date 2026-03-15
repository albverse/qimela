extends Area2D
class_name GhostBomb

@export var light_energy: float = 5.0
var _timer: float = 2.0

func _ready() -> void:
	add_to_group("ghost_bomb")
	body_entered.connect(_on_body_entered)

func _physics_process(dt: float) -> void:
	_timer -= dt
	if _timer <= 0.0:
		_explode()

func _explode() -> void:
	if EventBus:
		EventBus.healing_burst.emit(light_energy)
	queue_free()

func _on_body_entered(body: Node) -> void:
	if body and body.is_in_group("player") and body.has_method("apply_damage"):
		body.call("apply_damage", 1, global_position)
		_explode()
