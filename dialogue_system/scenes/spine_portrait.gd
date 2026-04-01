@tool
extends Control
class_name SpinePortraitScene

## Spine 立绘场景
## 每个角色一个独立实例，包含 SpineSprite + BubbleAnchor
## 作为独立场景，方便美术调控位置与尺寸

const LOG_PREFIX: String = "[SpinePortraitScene]"

@export var debug_log: bool = false
@export var portrait_scale: Vector2 = Vector2(1.0, 1.0):
	set(value):
		portrait_scale = value
		if is_node_ready() and _spine_container != null:
			_spine_container.scale = portrait_scale

@export var portrait_offset: Vector2 = Vector2.ZERO:
	set(value):
		portrait_offset = value
		if is_node_ready() and _spine_container != null:
			_spine_container.position = portrait_offset

@export var flip_horizontal: bool = false:
	set(value):
		flip_horizontal = value
		if is_node_ready() and _spine_container != null:
			var sx: float = -absf(portrait_scale.x) if flip_horizontal else absf(portrait_scale.x)
			_spine_container.scale.x = sx

## 控制器
var portrait_controller: SpinePortraitController = null

## 内部节点
var _spine_container: Node2D = null
var _spine_sprite: Node = null
var _bubble_anchor: Marker2D = null


func _ready() -> void:
	_spine_container = $SpineContainer as Node2D
	_bubble_anchor = $SpineContainer/BubbleAnchor as Marker2D

	# 查找 SpineSprite 子节点
	for child: Node in _spine_container.get_children():
		if child.get_class() == "SpineSprite":
			_spine_sprite = child
			break

	if _spine_container != null:
		_spine_container.scale = portrait_scale
		_spine_container.position = portrait_offset
		if flip_horizontal:
			_spine_container.scale.x = -absf(portrait_scale.x)


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


func get_bubble_anchor_global_position() -> Vector2:
	if _bubble_anchor != null:
		return _bubble_anchor.global_position
	return global_position


func get_spine_sprite() -> Node:
	return _spine_sprite
