extends MonsterBase
class_name MonsterFly

@export var move_speed: float = 90.0
@export var float_amp: float = 12.0
@export var float_freq: float = 2.4
@export var visible_time: float = 0.0
@export var visible_time_max: float = 6.0
@export var opacity_full_threshold: float = 4.0

var _base_y: float = 0.0
var _t: float = 0.0
var _dir: int = 1
var _is_visible: bool = false
var _visible_sources: Dictionary = {} # source_id -> true
var _pending_light_sources: Dictionary = {} # source_id -> {area, remaining}

@onready var _hurtbox: Area2D = get_node_or_null(^"Hurtbox") as Area2D
@onready var _body_shape: CollisionShape2D = get_node_or_null(^"CollisionShape2D") as CollisionShape2D


func _ready() -> void:
	add_to_group("flying_monster")
	# 你原来的 _ready 逻辑继续放下面
	max_hp = 3
	super._ready()
	_base_y = global_position.y
	EventBus.thunder_burst.connect(_on_thunder_burst)
	_switch_to_invisible()


func _physics_process(dt: float) -> void:
	_update_light_sources(dt)
	_update_visibility(dt)
	super._physics_process(dt)


func _on_thunder_burst(add_seconds: float) -> void:
	visible_time = min(visible_time + add_seconds, visible_time_max)


func _on_light_started(source_id: int, remaining_time: float, source_light_area: Area2D) -> void:
	if source_light_area == null:
		return
	_pending_light_sources[source_id] = {
		"area": source_light_area,
		"remaining": remaining_time,
	}
	_try_apply_light_source(source_id)


func _on_light_finished(source_id: int) -> void:
	_pending_light_sources.erase(source_id)
	_visible_sources.erase(source_id)


func _update_light_sources(dt: float) -> void:
	if _pending_light_sources.is_empty():
		return
	var expired: Array[int] = []
	for source_id in _pending_light_sources.keys():
		var data: Dictionary = _pending_light_sources[source_id]
		var remaining: float = float(data.get("remaining", 0.0)) - dt
		if remaining <= 0.0:
			expired.append(source_id)
			continue
		data["remaining"] = remaining
		_pending_light_sources[source_id] = data
		_try_apply_light_source(source_id)
	for source_id in expired:
		_pending_light_sources.erase(source_id)


func _try_apply_light_source(source_id: int) -> void:
	if _visible_sources.has(source_id):
		return
	if _light_receiver == null:
		return
	var data: Dictionary = _pending_light_sources.get(source_id, {})
	var area: Area2D = data.get("area") as Area2D
	if area == null:
		return
	if not area.overlaps_area(_light_receiver):
		return
	var remaining: float = float(data.get("remaining", 0.0))
	if remaining <= 0.0:
		return
	visible_time = min(visible_time + remaining, visible_time_max)
	_visible_sources[source_id] = true
	_pending_light_sources.erase(source_id)


func _update_visibility(dt: float) -> void:
	if visible_time > 0.0:
		if not _is_visible:
			_switch_to_visible()

		var alpha: float = 1.0
		if visible_time < opacity_full_threshold and opacity_full_threshold > 0.0:
			alpha = clampf(visible_time / opacity_full_threshold, 0.0, 1.0)

		if sprite != null:
			var m: Color = sprite.modulate
			m.a = alpha
			sprite.modulate = m

		visible_time = max(visible_time - dt, 0.0)
		if visible_time <= 0.0:
			visible_time = 0.0
			_switch_to_invisible()
	else:
		if _is_visible:
			_switch_to_invisible()


func _switch_to_visible() -> void:
	_is_visible = true
	if sprite != null:
		sprite.visible = true
	if _hurtbox != null:
		_hurtbox.set_deferred("monitorable", true)
	if _body_shape != null:
		_body_shape.set_deferred("disabled", false)


func _switch_to_invisible() -> void:
	_is_visible = false
	if sprite != null:
		sprite.visible = false
		var m: Color = sprite.modulate
		m.a = 0.0
		sprite.modulate = m
	if _hurtbox != null:
		_hurtbox.set_deferred("monitorable", false)
	if _body_shape != null:
		_body_shape.set_deferred("disabled", true)

	if _linked_player != null:
		for slot in _linked_slots:
			_linked_player.call("force_dissolve_chain", slot)
		_linked_slots.clear()
		_linked_player = null

func _do_move(dt: float) -> void:
	if weak:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	_t += dt
	velocity.x = float(_dir) * move_speed
	velocity.y = 0.0
	move_and_slide()

	# 简单来回飞
	if is_on_wall():
		_dir *= -1

	# 漂浮
	global_position.y = _base_y + sin(_t * TAU * float_freq) * float_amp
