extends Node2D

@export var line_path: NodePath
@export var segment_count: int = 18
@export var damping: float = 0.90
@export var stiffness: float = 0.55
@export var gravity: float = 0.0
@export var iterations: int = 6   # 约束迭代次数（原先写死6）

var _line: Line2D
var _pts: PackedVector2Array = PackedVector2Array()
var _prev: PackedVector2Array = PackedVector2Array()
var _active: bool = false

var _start_world: Vector2 = Vector2.ZERO
var _end_world: Vector2 = Vector2.ZERO


func _ready() -> void:
	_line = get_node_or_null(line_path) as Line2D
	if _line == null:
		push_error("RopeSim2D: line_path is invalid.")
		return

	_ensure_buffers()
	_prealloc_line_points()
	_line.visible = _active


func _ensure_buffers() -> void:
	var n: int = max(segment_count + 1, 2)
	if _pts.size() != n:
		_pts.resize(n)
		_prev.resize(n)
		for i in range(n):
			_pts[i] = Vector2.ZERO
			_prev[i] = Vector2.ZERO


func _prealloc_line_points() -> void:
	if _line == null:
		return
	var n: int = _pts.size()
	if _line.get_point_count() != n:
		_line.clear_points()
		for _i in range(n):
			_line.add_point(Vector2.ZERO)


func set_active(v: bool) -> void:
	_active = v
	if _line:
		_line.visible = v


func reset(start_world: Vector2, end_world: Vector2) -> void:
	_start_world = start_world
	_end_world = end_world

	_ensure_buffers()
	_prealloc_line_points()

	var n: int = _pts.size()
	var last: int = n - 1
	var step: float = 1.0 / float(last)

	for i in range(n):
		var t: float = float(i) * step
		var p: Vector2 = _start_world.lerp(_end_world, t)
		_pts[i] = p
		_prev[i] = p

	_apply_to_line_fast()


func set_ends(start_world: Vector2, end_world: Vector2) -> void:
	_start_world = start_world
	_end_world = end_world


func _physics_process(_dt: float) -> void:
	if not _active:
		return
	if _line == null:
		return

	# 如你在运行中改了 segment_count，确保结构一致
	_ensure_buffers()
	_prealloc_line_points()

	var n: int = _pts.size()
	var last: int = n - 1

	# 端点锁定：0=手，末端=钩子
	_pts[0] = _start_world
	_pts[last] = _end_world

	# Verlet 积分
	for i in range(1, last):
		var cur: Vector2 = _pts[i]
		var vel: Vector2 = (cur - _prev[i]) * damping
		_prev[i] = cur
		_pts[i] = cur + vel + Vector2(0.0, gravity)

	# 约束迭代（让“绳段长度”趋于均匀）
	var seg_len: float = _start_world.distance_to(_end_world) / float(last)
	for _k in range(iterations):
		_pts[0] = _start_world
		_pts[last] = _end_world

		for i in range(last):
			var a: Vector2 = _pts[i]
			var b: Vector2 = _pts[i + 1]
			var delta: Vector2 = b - a
			var d: float = maxf(delta.length(), 0.0001)
			var diff: float = (d - seg_len) / d
			var adjust: Vector2 = delta * (0.5 * stiffness * diff)

			if i != 0:
				_pts[i] += adjust
			if i + 1 != last:
				_pts[i + 1] -= adjust

	_apply_to_line_fast()


func _apply_to_line_fast() -> void:
	if _line == null:
		return
	var n: int = _pts.size()
	for i in range(n):
		_line.set_point_position(i, _line.to_local(_pts[i]))
