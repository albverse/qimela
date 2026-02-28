extends Node2D
class_name RestArea

## StoneMaskBird 回巢点：
## - 自动加入 rest_area 组
## - 生命值=3，可被玩家武器摧毁
## - 同一时刻仅允许一只 StoneMaskBird 占用

@export var max_hp: int = 3
var hp: int = 3
var is_broken: bool = false

var _occupying_bird_ref: WeakRef = null
@onready var _sprite: Sprite2D = get_node_or_null("Sprite2D") as Sprite2D
@onready var _hurt_shape: CollisionShape2D = get_node_or_null("Hurtbox/CollisionShape2D") as CollisionShape2D


func _ready() -> void:
	hp = max_hp
	add_to_group("rest_area")
	remove_from_group("rest_area_break")
	_update_visual_state()


func apply_hit(hit: HitData) -> bool:
	if hit == null:
		return false
	if hp <= 0:
		return false
	var real_damage: int = maxi(int(hit.damage), 1)
	hp = maxi(hp - real_damage, 0)
	_flash_once()
	_update_visual_state()
	if hp <= 0:
		_break_to_ruin()
	return true


func is_arrived(bird: Node2D) -> bool:
	if bird == null or not is_instance_valid(bird):
		return false
	if _hurt_shape == null or _hurt_shape.shape == null:
		return false

	var local := _hurt_shape.to_local(bird.global_position)
	var shape := _hurt_shape.shape
	if shape is CircleShape2D:
		return local.length_squared() <= pow((shape as CircleShape2D).radius, 2)
	if shape is RectangleShape2D:
		var ext := (shape as RectangleShape2D).size * 0.5
		return absf(local.x) <= ext.x and absf(local.y) <= ext.y
	if shape is CapsuleShape2D:
		var cap := shape as CapsuleShape2D
		var half_h := cap.height * 0.5
		var r := cap.radius
		if absf(local.x) <= r and absf(local.y) <= half_h:
			return true
		var top_center := Vector2(0.0, -half_h)
		var bot_center := Vector2(0.0, half_h)
		return local.distance_squared_to(top_center) <= r * r or local.distance_squared_to(bot_center) <= r * r
	return false


func on_chain_hit(_player: Node, _slot: int) -> int:
	return 0


func reserve_for(bird: Node2D) -> bool:
	if bird == null or not is_instance_valid(bird):
		return false
	if is_broken:
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
	if is_broken:
		return false
	return cur == null or cur == bird


func repair_one_point() -> bool:
	if not is_broken:
		return false
	hp = mini(hp + 1, max_hp)
	_update_visual_state()
	if hp >= max_hp:
		_restore_from_break()
		return true
	return false


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


func _break_to_ruin() -> void:
	is_broken = true
	hp = 0
	remove_from_group("rest_area")
	add_to_group("rest_area_break")
	_occupying_bird_ref = null
	_set_inactive()


func _restore_from_break() -> void:
	is_broken = false
	hp = max_hp
	remove_from_group("rest_area_break")
	add_to_group("rest_area")
	_set_active()


func _set_inactive() -> void:
	if _sprite:
		_sprite.visible = true
		_sprite.self_modulate = Color(0.35, 0.35, 0.35, 1.0)
	var hurtbox := get_node_or_null("Hurtbox") as Area2D
	if hurtbox:
		hurtbox.monitoring = false
		hurtbox.monitorable = false


func _set_active() -> void:
	if _sprite:
		_sprite.visible = true
	var hurtbox := get_node_or_null("Hurtbox") as Area2D
	if hurtbox:
		hurtbox.monitoring = true
		hurtbox.monitorable = true
	_update_visual_state()


func _update_visual_state() -> void:
	if _sprite == null or max_hp <= 0:
		return
	if is_broken:
		_sprite.self_modulate = Color(0.35, 0.35, 0.35, 1.0)
		return
	var ratio := clampf(float(hp) / float(max_hp), 0.0, 1.0)
	_sprite.self_modulate = Color(1.0, ratio, ratio, 1.0)
