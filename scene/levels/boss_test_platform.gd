extends StaticBody2D

@export var disappear_delay: float = 2.0
@export var recover_delay: float = 3.0

@onready var _shape: CollisionShape2D = $CollisionShape2D
var _occupied: bool = false

func _ready() -> void:
	$Area2D.body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node) -> void:
	if _occupied:
		return
	if not body.is_in_group("player"):
		return
	_occupied = true
	await get_tree().create_timer(disappear_delay).timeout
	_shape.set_deferred("disabled", true)
	await get_tree().create_timer(recover_delay).timeout
	_shape.set_deferred("disabled", false)
	_occupied = false
