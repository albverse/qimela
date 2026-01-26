extends MonsterBase
class_name MonsterFly

@export var move_speed: float = 90.0
@export var float_amp: float = 12.0
@export var float_freq: float = 2.4

@export var visible_time: float = 0.0
@export var visible_time_max: float = 6.0
@export var opacity_full_threshold: float = 3.0
@export var fade_curve: Curve = null

var _base_y: float = 0.0
var _t: float = 0.0
var _dir: int = 1
var _is_visible: bool = false

var _saved_body_layer: int = -1
var _saved_body_mask: int = -1

@export var light_node_path: NodePath = ^"PointLight2D"
@onready var _point_light: PointLight2D = get_node_or_null(light_node_path) as PointLight2D


func _ready() -> void:
	add_to_group("flying_monster")
	
	attribute_type = AttributeType.LIGHT
	max_hp = 3
	
	_saved_body_layer = collision_layer
	_saved_body_mask = collision_mask
	
	super._ready()
	
	_base_y = global_position.y
	
	if visible_time <= 0.0:
		_switch_to_invisible()
	else:
		_switch_to_visible()


func _physics_process(dt: float) -> void:
	_update_visibility(dt)
	super._physics_process(dt)


func _update_visibility(dt: float) -> void:
	if light_counter > 0.0:
		var transfer = min(light_counter, dt * 10.0)
		visible_time += transfer
		light_counter -= transfer
		visible_time = min(visible_time, visible_time_max)
	
	if visible_time > 0.0:
		if not _is_visible:
			_switch_to_visible()
		
		_update_opacity()
		
		visible_time -= dt
		visible_time = max(visible_time, 0.0)
	else:
		if _is_visible:
			_on_visibility_timeout()


func _update_opacity() -> void:
	if sprite == null:
		return
	
	var alpha: float
	
	if visible_time >= opacity_full_threshold:
		alpha = 1.0
	else:
		var t = visible_time / opacity_full_threshold
		if fade_curve != null:
			alpha = fade_curve.sample(t)
		else:
			alpha = lerp(0.0, 1.0, t)
	
	sprite.modulate.a = alpha
	
	if _point_light:
		_point_light.energy = alpha * 1.0


func _switch_to_visible() -> void:
	_is_visible = true
	
	if _saved_body_layer != -1:
		collision_layer = _saved_body_layer
		collision_mask = _saved_body_mask
	
	if sprite:
		sprite.visible = true
		sprite.modulate.a = 1.0
	
	var hurtbox := get_node_or_null("Hurtbox") as Area2D
	if hurtbox:
		hurtbox.set_deferred("monitorable", true)
		hurtbox.set_deferred("monitoring", true)
		
		var hurtbox_shape := hurtbox.get_node_or_null("CollisionShape2D") as CollisionShape2D
		if hurtbox_shape:
			hurtbox_shape.disabled = false
	
	
	if _point_light:
		_point_light.enabled = true
	
	print("[%s] 显形: visible_time=%.1f" % [name, visible_time])


func _switch_to_invisible() -> void:
	_is_visible = false
	
	collision_layer = 0
	
	if sprite:
		sprite.visible = false
		sprite.modulate.a = 0.0
	
	var hurtbox := get_node_or_null("Hurtbox") as Area2D
	if hurtbox:
		hurtbox.set_deferred("monitorable", false)
		hurtbox.set_deferred("monitoring", false)
		
		var hurtbox_shape := hurtbox.get_node_or_null("CollisionShape2D") as CollisionShape2D
		if hurtbox_shape:
			hurtbox_shape.disabled = true
	
	
	if _point_light:
		_point_light.enabled = false
	
	print("[%s] 隐身（collision_layer=0，可碰撞）" % name)


func _on_visibility_timeout() -> void:
	print("[%s] ========== 归零处理开始 ==========" % name)
	print("[%s] _linked_player: %s" % [name, _linked_player])
	print("[%s] _linked_slots: %s" % [name, _linked_slots])
	
	_switch_to_invisible()
	_force_release_all_chains()
	
	
	print("[%s] ========== 归零处理结束 ==========" % name)


func _force_release_all_chains() -> void:
	if _linked_slots.is_empty():
		print("[%s] 无链接，跳过断链" % name)
		return
	
	var slots: Array[int] = _linked_slots.duplicate()
	var p: Node = _linked_player
	
	_linked_slots.clear()
	_linked_player = null
	
	print("[%s] 尝试断链: player=%s, slots=%s" % [name, p, slots])
	
	if p == null:
		push_error("[%s] _linked_player 为 null！" % name)
		return
	
	if not is_instance_valid(p):
		push_error("[%s] _linked_player 已失效！" % name)
		return
	
	if not p.has_method("force_dissolve_chain"):
		push_error("[%s] Player 没有 force_dissolve_chain 方法！" % name)
		return
	
	for s in slots:
		print("[%s] 调用 player.force_dissolve_chain(%d)" % [name, s])
		p.call("force_dissolve_chain", s)
	
	print("[%s] 强制断链完成: %d条" % [name, slots.size()])


func _do_move(dt: float) -> void:
	if weak:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	_t += dt
	velocity.x = float(_dir) * move_speed
	velocity.y = 0.0
	move_and_slide()

	if is_on_wall():
		_dir *= -1

	global_position.y = _base_y + sin(_t * TAU * float_freq) * float_amp
