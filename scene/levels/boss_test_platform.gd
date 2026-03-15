extends StaticBody2D

@export var collapse_delay: float = 2.0
@export var recover_delay: float = 3.0
var _busy: bool = false

@onready var _shape: CollisionShape2D = get_node_or_null("CollisionShape2D") as CollisionShape2D
@onready var _area: Area2D = get_node_or_null("Trigger") as Area2D

func _ready() -> void:
	if _area:
		_area.body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node) -> void:
	if _busy:
		return
	if body == null or not body.is_in_group("player"):
		return
	_busy = true
	await get_tree().create_timer(collapse_delay).timeout
	if _shape:
		_shape.set_deferred("disabled", true)
	await get_tree().create_timer(recover_delay).timeout
	if _shape:
		_shape.set_deferred("disabled", false)
	_busy = false
