extends StaticBody2D
class_name DisappearingPlatform
@export var vanish_delay: float = 2.0
@export var recover_delay: float = 3.0
@onready var _shape: CollisionShape2D = $CollisionShape2D
var _busy: bool = false
func _on_body_entered(body: Node) -> void:
	if _busy or body == null or not body.is_in_group("player"):
		return
	_busy = true
	await get_tree().create_timer(vanish_delay).timeout
	if _shape != null:
		_shape.set_deferred("disabled", true)
	await get_tree().create_timer(recover_delay).timeout
	if _shape != null:
		_shape.set_deferred("disabled", false)
	_busy = false
