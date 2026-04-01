@tool
extends Control
class_name SpinePortraitScene

## Spine 立绘场景
## 每个角色一个独立实例，包含 SpineSprite + BubbleAnchor
## 作为独立场景供美术调控：缩放、偏移、入场动画参数均可在编辑器中调整
##
## 【美术使用说明】
## 1. 拖动 SpineContainer 改变立绘在场景中的位置
## 2. 调整 portrait_scale 改变立绘大小
## 3. slide_in_* 参数控制入场滑入动画
## 4. BubbleAnchor (Marker2D) 决定气泡相对立绘的锚定位置

const LOG_PREFIX: String = "[SpinePortraitScene]"

@export var debug_log: bool = false

## ── 立绘基础参数 ──
@export_group("Portrait Transform")
## 立绘缩放（不含翻转，美术可直接调数值）
@export var portrait_scale: Vector2 = Vector2(1.0, 1.0):
	set(value):
		portrait_scale = value
		if is_node_ready() and _spine_container != null:
			_spine_container.scale = portrait_scale

## 立绘偏移（相对于本节点原点）
@export var portrait_offset: Vector2 = Vector2.ZERO:
	set(value):
		portrait_offset = value
		if is_node_ready() and _spine_container != null:
			_spine_container.position = portrait_offset

## ── 入场滑入动画参数 ──
@export_group("Slide-In Animation")
## 是否启用入场滑入
@export var slide_in_enabled: bool = true
## 滑入起始偏移量（正值 = 从右边屏幕外滑入，负值 = 从左边屏幕外滑入）
## player 侧建议正值（从右侧滑入），other 侧建议负值（从左侧滑入）
@export var slide_in_offset_x: float = 600.0
## 滑入持续时间
@export var slide_in_duration: float = 0.6
## 贝塞尔缓动：ease 模式
@export_enum("Ease In", "Ease Out", "Ease In Out", "Ease Out In") var slide_in_ease: int = 2
## 贝塞尔缓动：transition 模式
@export_enum("Linear", "Sine", "Quint", "Quart", "Quad", "Expo", "Elastic", "Cubic", "Circ", "Bounce", "Back", "Spring") var slide_in_trans: int = 7

## 控制器
var portrait_controller: SpinePortraitController = null

## 内部节点
var _spine_container: Node2D = null
var _spine_sprite: Node = null
var _bubble_anchor: Marker2D = null
var _slide_in_tween: Tween = null
var _original_position: Vector2 = Vector2.ZERO


func _ready() -> void:
	_spine_container = $SpineContainer as Node2D
	_bubble_anchor = $SpineContainer/BubbleAnchor as Marker2D

	# 查找 SpineSprite 子节点
	if _spine_container != null:
		for child: Node in _spine_container.get_children():
			if child.get_class() == "SpineSprite":
				_spine_sprite = child
				break

	if _spine_container != null:
		_spine_container.scale = portrait_scale
		_spine_container.position = portrait_offset

	_original_position = position


func setup_controller() -> void:
	## 初始化 SpinePortraitController
	if _spine_sprite == null:
		push_warning("%s No SpineSprite found in SpineContainer" % LOG_PREFIX)
		return

	portrait_controller = SpinePortraitController.new()
	portrait_controller.debug_log = debug_log
	portrait_controller.name = "PortraitController"
	add_child(portrait_controller)
	portrait_controller.setup(_spine_sprite)


func play_slide_in() -> void:
	## 播放入场滑入动画（贝塞尔缓入缓出）
	if not slide_in_enabled:
		return

	# 记录目标位置
	var target_pos: Vector2 = _original_position

	# 设置起始位置（从屏幕外滑入）
	position = Vector2(target_pos.x + slide_in_offset_x, target_pos.y)
	modulate.a = 0.0

	# 停止旧动画
	if _slide_in_tween != null and _slide_in_tween.is_valid():
		_slide_in_tween.kill()

	_slide_in_tween = create_tween()
	_slide_in_tween.set_parallel(true)

	# 位置滑入
	_slide_in_tween.tween_property(
		self, "position", target_pos, slide_in_duration
	).set_ease(slide_in_ease).set_trans(slide_in_trans)

	# 淡入
	_slide_in_tween.tween_property(
		self, "modulate:a", 1.0, slide_in_duration * 0.5
	).set_ease(Tween.EASE_OUT)

	if debug_log:
		print("%s Slide-in from offset_x=%s, duration=%s" % [
			LOG_PREFIX, str(slide_in_offset_x), str(slide_in_duration)
		])


func play_slide_out(on_complete: Callable = Callable()) -> void:
	## 播放退场滑出动画
	var exit_pos: Vector2 = Vector2(position.x + slide_in_offset_x, position.y)

	if _slide_in_tween != null and _slide_in_tween.is_valid():
		_slide_in_tween.kill()

	_slide_in_tween = create_tween()
	_slide_in_tween.set_parallel(true)
	_slide_in_tween.tween_property(
		self, "position", exit_pos, slide_in_duration * 0.8
	).set_ease(Tween.EASE_IN).set_trans(slide_in_trans)
	_slide_in_tween.tween_property(
		self, "modulate:a", 0.0, slide_in_duration * 0.6
	).set_ease(Tween.EASE_IN)

	if on_complete.is_valid():
		_slide_in_tween.finished.connect(on_complete)


func get_bubble_anchor_global_position() -> Vector2:
	if _bubble_anchor != null:
		return _bubble_anchor.global_position
	return global_position


func get_spine_sprite() -> Node:
	return _spine_sprite
