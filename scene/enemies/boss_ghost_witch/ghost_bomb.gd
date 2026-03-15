extends CharacterBody2D
class_name GhostBomb

@export var move_speed: float = 120.0
@export var s_amplitude: float = 36.0
@export var s_frequency: float = 6.0

var _player: Node2D = null
var _light_energy: float = 5.0
var _time: float = 0.0
var _exploding: bool = false

func setup(player: Node2D, light_energy: float) -> void:
	_player = player
	_light_energy = light_energy

func _ready() -> void:
	$HurtArea.area_entered.connect(_on_hurt_area_entered)
	$ExplosionArea.monitoring = false
	$LightArea.monitoring = false

func _physics_process(dt: float) -> void:
	if _exploding:
		return
	_time += dt
	if _player and is_instance_valid(_player):
		var dir := (_player.global_position - global_position).normalized()
		velocity = dir * move_speed
		velocity.x += sin(_time * s_frequency) * s_amplitude
	move_and_slide()

func _on_hurt_area_entered(area: Area2D) -> void:
	if area.is_in_group("ghost_fist_hitbox"):
		queue_free()
		return
	if area.get_parent() and area.get_parent().is_in_group("player"):
		_begin_explode()

func _begin_explode() -> void:
	if _exploding:
		return
	_exploding = true
	await get_tree().create_timer(1.0).timeout
	$ExplosionArea.monitoring = true
	$LightArea.monitoring = true
	for b in $ExplosionArea.get_overlapping_bodies():
		if b.is_in_group("player") and b.has_method("apply_damage"):
			b.call("apply_damage", 1, global_position)
	if EventBus:
		EventBus.healing_burst.emit(_light_energy)
	queue_free()
