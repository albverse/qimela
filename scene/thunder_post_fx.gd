extends ColorRect
class_name ThunderPostFX

# 你要求：0.1 秒内出现，0.8 秒内消失
@export var rise_time: float = 0.10
@export var fall_time: float = 0.80
@export var peak_amount: float = 1.0

# 白闪节奏：更像真实雷（非常短的亮一下）
@export var flash_rise: float = 0.02
@export var flash_fall: float = 0.18
@export var flash_peak: float = 1.0

@onready var _mat: ShaderMaterial = material as ShaderMaterial
var _tw: Tween

func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_set_amount(0.0)
	_set_flash(0.0)

func thunder_flash() -> void:
	if _tw:
		_tw.kill()

	visible = true
	_set_amount(0.0)
	_set_flash(0.0)

	_tw = create_tween()

	# amount：0 -> 1（0.1s）-> 0（0.8s）
	_tw.tween_method(_set_amount, 0.0, peak_amount, rise_time)\
		.set_trans(Tween.TRANS_LINEAR).set_ease(Tween.EASE_OUT)
	_tw.tween_method(_set_amount, peak_amount, 0.0, fall_time)\
		.set_trans(Tween.TRANS_LINEAR).set_ease(Tween.EASE_OUT)

	# flash：0 -> 1（极短）-> 0（短衰减）
	# 用并行动画，不影响 amount 的节奏
	_tw.parallel().tween_method(_set_flash, 0.0, flash_peak, flash_rise)\
		.set_trans(Tween.TRANS_LINEAR).set_ease(Tween.EASE_OUT)
	_tw.parallel().tween_method(_set_flash, flash_peak, 0.0, flash_fall)\
		.set_delay(flash_rise)\
		.set_trans(Tween.TRANS_LINEAR).set_ease(Tween.EASE_OUT)

	_tw.finished.connect(func():
		_set_amount(0.0)
		_set_flash(0.0)
		visible = false
	)

func _set_amount(v: float) -> void:
	if _mat:
		_mat.set_shader_parameter("amount", v)

func _set_flash(v: float) -> void:
	if _mat:
		_mat.set_shader_parameter("flash", v)
