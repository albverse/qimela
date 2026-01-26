extends CharacterBody2D
class_name ChimeraA

# ===== 互动移动参数 =====
@export var gravity: float = 1500.0
@export var move_speed: float = 170.0
@export var accel: float = 1400.0
@export var stop_threshold_x: float = 6.0
@export var x_offset: float = 0.0

var _hurtbox_original_layer: int = -1
@onready var _hurtbox: Area2D = get_node_or_null("Hurtbox") as Area2D

var _player: Node2D = null
var _linked: bool = false
var _linked_slot: int = -1  # -1表示未被链接
var _wander_dir: int = 0
var _wander_t: float = 0.0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

@export var flash_time: float = 0.2
@export var visual_item_path: NodePath = NodePath("")

@onready var sprite: CanvasItem = _find_visual()
var _flash_tw: Tween = null
@export var ui_icon: Texture2D = preload("res://yaoshi.png")


func _ready() -> void:
	# 让 Player 的锁链射线识别它（Player 里检测 group: "chimera"）
	add_to_group("chimera")
	_rng.randomize()
	_pick_next_wander()

# 兼容 Player：spawn 后会调用 setup(self)
func setup(p: Node2D) -> void:
	set_player(p)

func set_player(p: Node2D) -> void:
	_player = p


# Player 的射线命中后会先调用 on_chain_hit。
# 返回 1 表示：锁链进入 LINKED（保持链接），并触发互动。
func on_chain_hit(_player_ref: Node, slot: int) -> int:
	on_chain_attached(slot)
	return 1

# Player：锁链链接到奇美拉时调用
func on_chain_attached(slot: int) -> void:
	_linked = true
	_linked_slot = slot
	_flash_once()
	
	# 禁用Hurtbox让另一条链穿透
	if _hurtbox != null:
		_hurtbox_original_layer = _hurtbox.collision_layer
		_hurtbox.collision_layer = 0

func on_chain_detached(slot: int) -> void:
	if slot == _linked_slot:
		_linked = false
		_linked_slot = -1
		
		# 恢复Hurtbox
		if _hurtbox != null and _hurtbox_original_layer >= 0:
			_hurtbox.collision_layer = _hurtbox_original_layer

func is_occupied_by_other_chain(requesting_slot: int) -> bool:
	return _linked_slot >= 0 and _linked_slot != requesting_slot
	
func _physics_process(dt: float) -> void:
	velocity.y += gravity * dt

	if _linked and _player != null and is_instance_valid(_player):
		var target_x: float = _player.global_position.x + x_offset
		var dx: float = target_x - global_position.x

		if absf(dx) <= stop_threshold_x:
			velocity.x = move_toward(velocity.x, 0.0, accel * dt)
		else:
			var dir: float = signf(dx)
			var desired: float = dir * move_speed
			velocity.x = move_toward(velocity.x, desired, accel * dt)
	else:
		_wander_t -= dt
		if _wander_t <= 0.0:
			_pick_next_wander()
		var desired := float(_wander_dir) * move_speed
		velocity.x = move_toward(velocity.x, desired, accel * dt)

	move_and_slide()

func _find_visual() -> CanvasItem:
	if visual_item_path != NodePath(""):
		var v := get_node_or_null(visual_item_path) as CanvasItem
		if v != null:
			return v

	var s := get_node_or_null("Sprite2D") as CanvasItem
	if s != null:
		return s
	var vis := get_node_or_null("Visual") as CanvasItem
	if vis != null:
		return vis

	var stack: Array[Node] = []
	for ch in get_children():
		stack.append(ch)
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		var ci := n as CanvasItem
		if ci != null:
			return ci
		for ch2 in n.get_children():
			stack.append(ch2)

	return null

func _flash_once() -> void:
	if sprite == null:
		return
	if _flash_tw != null:
		_flash_tw.kill()
		_flash_tw = null

	var orig_mod: Color = sprite.modulate
	var orig_self: Color = sprite.self_modulate
	sprite.modulate = Color(1.0, 1.0, 1.0, orig_mod.a)
	sprite.self_modulate = Color(1.8, 1.8, 1.8, orig_self.a)
	_flash_tw = create_tween()
	_flash_tw.tween_property(sprite, "modulate", orig_mod, flash_time)
	_flash_tw.parallel().tween_property(sprite, "self_modulate", orig_self, flash_time)

func _pick_next_wander() -> void:
	_wander_dir = _rng.randi_range(-1, 1)
	_wander_t = _rng.randf_range(1.0, 4.0)

func get_ui_icon() -> Texture2D:
	return ui_icon

func get_attribute_type() -> int:
	return 0
func on_player_interact(p: Player) -> void:
	# 奇美拉互动逻辑（例如治疗、增益等）
	if p.has_method("heal"):
		p.call("heal", 1)
	print("[ChimeraA] 玩家互动：回复1心")
