extends Node
class_name WeatherController

@export var interval_min: float = 10.0 #打雷的最小间隔
@export var interval_max: float = 30.0 #打雷的最大间隔
@export var start_delay: float = 1.0

# requirements: thunder_burst(add_seconds=3)
@export var thunder_add_seconds: float = 3.0

# 动画名（AnimationPlayer里需要存在同名动画）
@export var thunder_animation: StringName = &"thunder"

@export var debug_print: bool = true

@onready var _timer: Timer = $ThunderTimer
@onready var _anim: AnimationPlayer = $AnimationPlayer

var _rng := RandomNumberGenerator.new()
var _emitted_this_cycle := false

func _ready() -> void:
	_rng.randomize()

	_timer.one_shot = true
	_timer.timeout.connect(_on_timer_timeout)

	if is_instance_valid(_anim):
		_anim.animation_finished.connect(_on_animation_finished)

	# 延迟启动，避免场景尚未稳定
	_schedule_next(start_delay)

func _schedule_next(delay: float = -1.0) -> void:
	var t := delay
	if t < 0.0:
		t = _rng.randf_range(interval_min, interval_max)
	_timer.start(max(t, 0.01))

func _on_timer_timeout() -> void:
	_start_thunder()

func _start_thunder() -> void:
	_emitted_this_cycle = false

	if is_instance_valid(_anim) and _anim.has_animation(thunder_animation):
		# 确保动画不Loop，否则会多次触发
		_anim.play(thunder_animation)
	else:
		# 若你还没做动画，给一个最小兜底：0.2s 后发一次 thunder_burst
		_fallback_emit_then_schedule()

func _fallback_emit_then_schedule() -> void:
	await get_tree().create_timer(0.2).timeout
	_emit_thunder_burst_once()
	_schedule_next()

# 让动画在 0.2s 那一帧调用这个方法（Call Method Track）
func anim_emit_thunder_burst() -> void:
	_emit_thunder_burst_once()

func _emit_thunder_burst_once() -> void:
	if _emitted_this_cycle:
		return
	_emitted_this_cycle = true

	# 每次打雷只触发一次事件（验收关键）
	if typeof(EventBus) != TYPE_NIL:
		if EventBus.has_method("emit_thunder_burst"):
			EventBus.emit_thunder_burst(thunder_add_seconds)
		else:
			# 兼容：若你EventBus没有封装函数
			EventBus.thunder_burst.emit(thunder_add_seconds)

	if debug_print:
		print("[Thunder] thunder_burst +", thunder_add_seconds)

func _on_animation_finished(name: StringName) -> void:
	if name == thunder_animation:
		# 动画结束后再安排下一次随机雷击
		_schedule_next()
