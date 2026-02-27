extends Node2D
class_name RestArea

## StoneMaskBird 回巢点：
## - 自动加入 rest_area 组
## - 生命值=3，可被玩家武器摧毁
## - 同一时刻仅允许一只 StoneMaskBird 占用

@export var max_hp: int = 3
var hp: int = 3

var _occupying_bird_ref: WeakRef = null
@onready var _sprite: Sprite2D = get_node_or_null("Sprite2D") as Sprite2D


func _ready() -> void:
	hp = max_hp
	add_to_group("rest_area")


func apply_hit(hit: HitData) -> bool:
	if hit == null:
		return false
	if hp <= 0:
		return false
	hp = max(hp - hit.damage, 0)
	_flash_once()
	if hp <= 0:
		queue_free()
	return true


func on_chain_hit(_player: Node, _slot: int) -> int:
	return 0


func reserve_for(bird: Node2D) -> bool:
	if bird == null or not is_instance_valid(bird):
		return false
	var cur := _get_occupying_bird()
	if cur != null and cur != bird:
		return false
	_occupying_bird_ref = weakref(bird)
	return true


func release_for(bird: Node2D) -> void:
	var cur := _get_occupying_bird()
	if cur == null:
		_occupying_bird_ref = null
		return
	if bird == cur:
		_occupying_bird_ref = null


func is_available_for(bird: Node2D) -> bool:
	var cur := _get_occupying_bird()
	return cur == null or cur == bird


func _get_occupying_bird() -> Node2D:
	if _occupying_bird_ref == null:
		return null
	var obj: Object = _occupying_bird_ref.get_ref()
	if obj == null:
		_occupying_bird_ref = null
		return null
	return obj as Node2D


func _flash_once() -> void:
	if _sprite == null:
		return
	var tw := create_tween()
	_sprite.modulate = Color(1.2, 1.2, 1.2, 1.0)
	tw.tween_property(_sprite, "modulate", Color.WHITE, 0.1)
