extends StaticBody2D
class_name FadingPlatform

@export var visible_duration: float = 2.0
@export var hidden_duration: float = 3.0

@onready var _shape: CollisionShape2D = $CollisionShape2D
var _timer: Timer
var _hidden: bool = false

func _ready() -> void:
	_timer = Timer.new()
	_timer.one_shot = true
	add_child(_timer)
	_timer.timeout.connect(_on_timer_timeout)
	_timer.start(visible_duration)

func _on_timer_timeout() -> void:
	_hidden = not _hidden
	if _shape != null:
		_shape.set_deferred("disabled", _hidden)
	visible = not _hidden
	_timer.start(hidden_duration if _hidden else visible_duration)
