extends EntityBase
class_name RestArea

@export var max_durability: int = 3
@export var rest_enter_radius: float = 36.0

var _occupying_bird: Node = null
var _reserved_bird: Node = null

func _ready() -> void:
	has_hp = true
	max_hp = max_durability
	hp = max_durability
	weak_hp = 0
	species_id = &"rest_area"
	add_to_group("rest_area")
	super._ready()


func _is_valid_ref(n: Node) -> bool:
	return n != null and is_instance_valid(n)


func can_accept_bird(bird: Node) -> bool:
	if not _is_valid_ref(_occupying_bird):
		_occupying_bird = null
	if not _is_valid_ref(_reserved_bird):
		_reserved_bird = null
	if _occupying_bird != null and _occupying_bird != bird:
		return false
	if _reserved_bird != null and _reserved_bird != bird:
		return false
	return true


func reserve_for_bird(bird: Node) -> bool:
	if bird == null:
		return false
	if not can_accept_bird(bird):
		return false
	_reserved_bird = bird
	return true


func occupy_by_bird(bird: Node) -> bool:
	if bird == null:
		return false
	if not can_accept_bird(bird):
		return false
	_occupying_bird = bird
	_reserved_bird = bird
	return true


func release_by_bird(bird: Node) -> void:
	if _occupying_bird == bird:
		_occupying_bird = null
	if _reserved_bird == bird:
		_reserved_bird = null


func apply_hit(hit: HitData) -> bool:
	if hit == null or not has_hp or hp <= 0:
		return false
	hp = max(hp - max(hit.damage, 1), 0)
	_flash_once()
	if hp <= 0:
		queue_free()
	return true


func on_chain_hit(_player: Node, _slot: int) -> int:
	if not has_hp or hp <= 0:
		return 0
	take_damage(1)
	return 0


func is_bird_arrived(bird: Node2D) -> bool:
	if bird == null or not is_instance_valid(bird):
		return false
	return global_position.distance_to(bird.global_position) <= rest_enter_radius
