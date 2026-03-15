extends StaticBody2D

@export var disable_after_sec: float = 2.0
@export var restore_after_sec: float = 3.0

@onready var _shape: CollisionShape2D = $CollisionShape2D

func _ready() -> void:
	_loop_toggle()

func _loop_toggle() -> void:
	while is_inside_tree():
		await get_tree().create_timer(disable_after_sec).timeout
		if _shape != null:
			_shape.set_deferred("disabled", true)
		await get_tree().create_timer(restore_after_sec).timeout
		if _shape != null:
			_shape.set_deferred("disabled", false)
