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
@export var slide_in_offset_x: float = 600.0
## 滑入持续时间
@export var slide_in_duration: float = 0.6
## 贝塞尔缓动：ease 模式
@export_enum("Ease In", "Ease Out", "Ease In Out", "Ease Out In") var slide_in_ease: int = 2
## 贝塞尔缓动：transition 模式
@export_enum("Linear", "Sine", "Quint", "Quart", "Quad", "Expo", "Elastic", "Cubic", "Circ", "Bounce", "Back", "Spring") var slide_in_trans: int = 7

## ── 抖动动效参数 ──
@export_group("Shake Effect")
## 抖动强度（像素）
@export var shake_intensity: float = 10.0
## 抖动持续时间
@export var shake_duration: float = 0.5
## 抖动频率（次/秒）
@export var shake_frequency: float = 25.0

## ── 淡入淡出参数 ──
@export_group("Fade Effect")
## 淡入持续时间
@export var fade_in_duration: float = 0.4
## 淡出持续时间
@export var fade_out_duration: float = 0.3

## 控制器
var portrait_controller: SpinePortraitController = null

## Shader 注册表：shader_id → ShaderMaterial（由外部在 configure_session 时注册）
var _shader_registry: Dictionary = {}

## 内部节点
var _spine_container: Node2D = null
var _spine_sprite: Node = null
var _bubble_anchor: Marker2D = null
var _slide_tween: Tween = null
var _effect_tween: Tween = null
var _original_position: Vector2 = Vector2.ZERO
var _current_shader_id: StringName = &""


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


## ── Shader 注册 ──

func register_shader(shader_id: String, shader_material: ShaderMaterial) -> void:
	## 注册 shader 到立绘 shader 注册表
	_shader_registry[shader_id] = shader_material
	if debug_log:
		print("%s Registered shader: %s" % [LOG_PREFIX, shader_id])


## ── Shader 附着/清除 ──

func apply_shader(shader_id: StringName) -> void:
	## 给当前立绘 SpineSprite 附着指定 shader
	if _spine_sprite == null:
		return
	var key: String = str(shader_id)
	if not _shader_registry.has(key):
		if debug_log:
			print("%s Shader '%s' not found in registry" % [LOG_PREFIX, key])
		return
	var mat: ShaderMaterial = _shader_registry[key] as ShaderMaterial
	if mat != null and _spine_sprite is CanvasItem:
		(_spine_sprite as CanvasItem).material = mat
		_current_shader_id = shader_id
		if debug_log:
			print("%s Applied shader: %s" % [LOG_PREFIX, key])


func clear_shader() -> void:
	## 清除立绘上附着的 shader
	if _spine_sprite != null and _spine_sprite is CanvasItem:
		(_spine_sprite as CanvasItem).material = null
		_current_shader_id = &""
		if debug_log:
			print("%s Cleared shader" % LOG_PREFIX)


## ── 控制器管理 ──

func setup_controller() -> void:
	## 初始化 SpinePortraitController
	if _spine_sprite == null:
		push_warning("%s No SpineSprite found in SpineContainer" % LOG_PREFIX)
		return

	if portrait_controller != null and is_instance_valid(portrait_controller):
		return

	portrait_controller = SpinePortraitController.new()
	portrait_controller.debug_log = debug_log
	portrait_controller.name = "PortraitController"
	add_child(portrait_controller)
	portrait_controller.setup(_spine_sprite)


func reset_controller() -> void:
	if portrait_controller != null and is_instance_valid(portrait_controller):
		portrait_controller.queue_free()
	portrait_controller = null


## ── 入场/退场动画 ──

func play_slide_in() -> void:
	## 播放入场滑入动画（贝塞尔缓入缓出 + 淡入）
	if not slide_in_enabled:
		return

	var target_pos: Vector2 = _original_position
	position = Vector2(target_pos.x + slide_in_offset_x, target_pos.y)
	modulate.a = 0.0

	_kill_slide_tween()
	_slide_tween = create_tween()
	_slide_tween.set_parallel(true)

	_slide_tween.tween_property(
		self, "position", target_pos, slide_in_duration
	).set_ease(slide_in_ease).set_trans(slide_in_trans)

	_slide_tween.tween_property(
		self, "modulate:a", 1.0, slide_in_duration * 0.5
	).set_ease(Tween.EASE_OUT)

	if debug_log:
		print("%s Slide-in from offset_x=%s, duration=%s" % [
			LOG_PREFIX, str(slide_in_offset_x), str(slide_in_duration)
		])


func play_slide_out(on_complete: Callable = Callable()) -> void:
	## 播放退场滑出动画
	var exit_pos: Vector2 = Vector2(position.x + slide_in_offset_x, position.y)

	_kill_slide_tween()
	_slide_tween = create_tween()
	_slide_tween.set_parallel(true)
	_slide_tween.tween_property(
		self, "position", exit_pos, slide_in_duration * 0.8
	).set_ease(Tween.EASE_IN).set_trans(slide_in_trans)
	_slide_tween.tween_property(
		self, "modulate:a", 0.0, slide_in_duration * 0.6
	).set_ease(Tween.EASE_IN)

	if on_complete.is_valid():
		_slide_tween.finished.connect(on_complete)


## ── 动效命令 ──

func play_effect(effect_name: StringName) -> void:
	## 统一动效入口，按 effect_name 分发
	match str(effect_name):
		"fade_in":
			play_fade_in()
		"fade_out":
			play_fade_out()
		"slide_in":
			play_slide_in()
		"slide_out":
			play_slide_out()
		"shake":
			play_shake()
		_:
			if debug_log:
				print("%s Unknown effect: %s" % [LOG_PREFIX, effect_name])


func play_fade_in() -> void:
	## 淡入效果（透明度 0 → 1）
	modulate.a = 0.0
	_kill_effect_tween()
	_effect_tween = create_tween()
	_effect_tween.tween_property(self, "modulate:a", 1.0, fade_in_duration).set_ease(Tween.EASE_OUT)


func play_fade_out() -> void:
	## 淡出效果（透明度 → 0）
	_kill_effect_tween()
	_effect_tween = create_tween()
	_effect_tween.tween_property(self, "modulate:a", 0.0, fade_out_duration).set_ease(Tween.EASE_IN)


func play_shake() -> void:
	## 抖动效果（表现角色惊讶/震惊）
	_kill_effect_tween()
	var base_pos: Vector2 = _original_position
	var step: float = 1.0 / shake_frequency
	var steps: int = int(shake_duration * shake_frequency)

	_effect_tween = create_tween()
	for i: int in range(steps):
		var decay: float = 1.0 - (float(i) / float(steps))
		var offset_x: float = randf_range(-shake_intensity, shake_intensity) * decay
		var offset_y: float = randf_range(-shake_intensity, shake_intensity) * decay
		_effect_tween.tween_property(
			self, "position",
			base_pos + Vector2(offset_x, offset_y),
			step
		)
	_effect_tween.tween_property(self, "position", base_pos, step)


## ── 查询 ──

func get_bubble_anchor_global_position() -> Vector2:
	if _bubble_anchor != null:
		return _bubble_anchor.global_position
	return global_position


func get_spine_sprite() -> Node:
	return _spine_sprite


## ── 内部 ──

func _kill_slide_tween() -> void:
	if _slide_tween != null and _slide_tween.is_valid():
		_slide_tween.kill()
	_slide_tween = null


func _kill_effect_tween() -> void:
	if _effect_tween != null and _effect_tween.is_valid():
		_effect_tween.kill()
	_effect_tween = null
