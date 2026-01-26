extends CharacterBody2D
class_name MonsterBase

# ===== 基础属性 =====
@export var max_hp: int = 3
@export var weak_hp: int = 1
@export var hit_stun_time: float = 0.1
@export var flash_time: float = 0.2
@export var weak_stun_time: float = 5.0
@export var weak_stun_extend_time: float = 3.0

# ===== 光/雷反应系统 =====
enum AttributeType { NORMAL, LIGHT, DARK }

@export var attribute_type: AttributeType = AttributeType.NORMAL
@export var light_counter: float = 0.0
@export var light_counter_max: float = 10.0
@export var thunder_add_seconds: float = 3.0

var _processed_light_sources: Dictionary = {}
var _thunder_processed_this_frame: bool = false

# ===== 光照接收器（修复：改用Hurtbox）=====
# 优先使用用户指定的LightReceiver，如果没有则fallback到Hurtbox
@export var light_receiver_path: NodePath = ^"Hurtbox"  # ← 修复：默认使用Hurtbox
@onready var _light_receiver: Area2D = get_node_or_null(light_receiver_path) as Area2D

var _active_light_sources: Dictionary = {}

# ===== 视觉 =====
@export var visual_item_path: NodePath = NodePath("")
@export var ui_icon: Texture2D = null
@onready var sprite: CanvasItem = _find_visual()

# ===== 运行时状态 =====
var hp: int = 3
var stunned_t: float = 0.0
var weak: bool = false
var weak_stun_t: float = 0.0
var _linked_player: Node = null
var _linked_slots: Array[int] = []
var _flash_tw: Tween = null

var _saved_collision_layer: int = -1
var _saved_collision_mask: int = -1
var _fusion_vanished: bool = false


func _ready() -> void:
	add_to_group("monster")
	hp = max_hp
	_update_weak_state()
	
	# 连接事件总线
	if EventBus:
		EventBus.thunder_burst.connect(_on_thunder_burst)
		EventBus.light_started.connect(_on_light_started)
		EventBus.light_finished.connect(_on_light_finished)
	
	# 连接光照接收器的area_entered
	if _light_receiver:
		_light_receiver.area_entered.connect(_on_light_area_entered)
	else:
		push_error("[%s] 警告：light_receiver 为 null！光照检测将失败。请确保场景中有 Hurtbox 或设置 light_receiver_path" % name)

func _physics_process(dt: float) -> void:
	# 光/雷计数衰减
	if light_counter > 0.0:
		light_counter -= dt
		light_counter = max(light_counter, 0.0)
	
	# 重置雷击处理标记
	_thunder_processed_this_frame = false
	
	# 原有逻辑
	if weak:
		if weak_stun_t > 0.0:
			weak_stun_t -= dt
			if weak_stun_t <= 0.0:
				weak_stun_t = 0.0
				_restore_from_weak()
		return
	if stunned_t > 0.0:
		stunned_t -= dt
		if stunned_t < 0.0:
			stunned_t = 0.0
			_release_linked_chains()
		return

	_do_move(dt)

func _do_move(_dt: float) -> void:
	pass

# ===== 光/雷反应逻辑 =====

func _on_thunder_burst(add_seconds: float) -> void:
	if _thunder_processed_this_frame:
		return
	_thunder_processed_this_frame = true
	
	var old_counter = light_counter
	light_counter += add_seconds
	light_counter = min(light_counter, light_counter_max)
	
	if light_counter != old_counter:
		print("[%s] 雷击: light_counter %.1f -> %.1f" % [name, old_counter, light_counter])
func on_light_exposure(remaining_time: float) -> void:
	var old_counter = light_counter
	light_counter += remaining_time
	light_counter = min(light_counter, light_counter_max)
	
	if light_counter != old_counter:
		print("[%s] 光照暴露: light_counter %.1f -> %.1f (+%.1f)" % [name, old_counter, light_counter, remaining_time])
		
func _on_light_started(source_id: int, remaining_time: float, source_light_area: Area2D) -> void:
	if _light_receiver == null or source_light_area == null:
		# 调试：打印警告
		if _light_receiver == null:
			push_error("[%s] _light_receiver 为 null，无法检测光照！" % name)
		return
	
	# 检查是否在光照范围内
	if not source_light_area.overlaps_area(_light_receiver):
		# 不在范围内，记录该光源
		_active_light_sources[source_id] = {
			"area": source_light_area,
			"remaining_time": remaining_time
		}
		print("[%s] 光照开始但不在范围内，记录source_id=%d" % [name, source_id])
		return
	
	# 在范围内，检查是否已处理过
	if _processed_light_sources.has(source_id):
		return
	
	# 首次暴露：增加计数
	_processed_light_sources[source_id] = true
	var old_counter = light_counter
	light_counter += remaining_time
	light_counter = min(light_counter, light_counter_max)
	
	if light_counter != old_counter:
		print("[%s] 光照开始: light_counter %.1f -> %.1f (+%.1f)" % [name, old_counter, light_counter, remaining_time])

func _on_light_finished(source_id: int) -> void:
	_processed_light_sources.erase(source_id)
	_active_light_sources.erase(source_id)

func _on_light_area_entered(area: Area2D) -> void:
	if area == null:
		return
	
	for source_id in _active_light_sources.keys():
		var light_data = _active_light_sources[source_id]
		if light_data["area"] == area:
			if _processed_light_sources.has(source_id):
				return
			
			var remaining = light_data["remaining_time"]
			_processed_light_sources[source_id] = true
			
			var old_counter = light_counter
			light_counter += remaining
			light_counter = min(light_counter, light_counter_max)
			
			if light_counter != old_counter:
				print("[%s] 后续进入光照: light_counter %.1f -> %.1f (+%.1f)" % [name, old_counter, light_counter, remaining])
			break

# ===== 原有逻辑 =====

func _update_weak_state() -> void:
	weak = (hp <= weak_hp)
	if weak and weak_stun_t <= 0.0:
		weak_stun_t = weak_stun_time

func _restore_from_weak() -> void:
	hp = max_hp
	weak = false
	weak_stun_t = 0.0
	_release_linked_chains()

func _release_linked_chains() -> void:
	var slots: Array[int] = _linked_slots.duplicate()
	_linked_slots.clear()

	var p: Node = _linked_player
	_linked_player = null

	if p == null or not is_instance_valid(p):
		return
	if not p.has_method("force_dissolve_chain"):
		return

	for s in slots:
		p.call("force_dissolve_chain", s)

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

func take_damage(amount: int) -> void:
	if hp <= 0:
		return
	hp = max(hp - amount, 0)
	_flash_once()
	stunned_t = max(stunned_t, hit_stun_time)
	_update_weak_state()
	if hp <= 0:
		queue_free()

func apply_stun(seconds: float, do_flash: bool = true) -> void:
	if seconds <= 0.0:
		return
	if do_flash:
		_flash_once()
	stunned_t = max(stunned_t, seconds)

func set_fusion_vanish(v: bool) -> void:
	if v:
		if not _fusion_vanished:
			_saved_collision_layer = collision_layer
			_saved_collision_mask = collision_mask
			_fusion_vanished = true
		collision_layer = 0
		collision_mask = 0
	else:
		if _fusion_vanished:
			collision_layer = _saved_collision_layer
			collision_mask = _saved_collision_mask
			_fusion_vanished = false

	var s := get_node_or_null("Sprite2D") as Node
	if s != null and s is CanvasItem:
		(s as CanvasItem).visible = not v

func on_chain_hit(_player: Node, _chain_index: int) -> int:
	if weak or stunned_t > 0.0:
		_linked_player = _player
		if not _linked_slots.has(_chain_index):
			_linked_slots.append(_chain_index)
		return 1

	take_damage(1)
	return 0

func on_chain_attached(slot: int) -> void:
	if not _linked_slots.has(slot):
		_linked_slots.append(slot)
	if weak:
		weak_stun_t += weak_stun_extend_time
	elif stunned_t > 0.0:
		stunned_t += weak_stun_extend_time

func on_chain_detached(slot: int) -> void:
	_linked_slots.erase(slot)
	if _linked_slots.is_empty():
		_linked_player = null

func get_ui_icon() -> Texture2D:
	return ui_icon

func get_attribute_type() -> int:
	return attribute_type
func get_weak_state() -> bool:
	return weak or stunned_t > 0.0
