extends CharacterBody2D
class_name MonsterBase

@export var max_hp: int = 3
@export var weak_hp: int = 1                 # hp==1 => 虚弱/昏迷
@export var hit_stun_time: float = 0.1       # 受击僵直
@export var flash_time: float = 0.2          # 闪烁时长
@export var weak_stun_time: float = 5.0      # 虚弱眩晕时长
@export var weak_stun_extend_time: float = 3.0 # 虚弱时被锁链锁定追加时长

# 受击闪白/变亮要作用到哪个“外观节点”（Sprite2D / AnimatedSprite2D / ColorRect 等 CanvasItem）。
# 为空则自动在子树里找第一个 CanvasItem。
@export var visual_item_path: NodePath = NodePath("")

var hp: int = 3
var stunned_t: float = 0.0
var weak: bool = false
var weak_stun_t: float = 0.0
var _linked_player: Node = null
var _linked_slots: Array[int] = []

@onready var sprite: CanvasItem = _find_visual()
var _flash_tw: Tween = null

var _saved_collision_layer: int = -1
var _saved_collision_mask: int = -1
var _fusion_vanished: bool = false


func _ready() -> void:
	add_to_group("monster")
	hp = max_hp
	_update_weak_state()

func _physics_process(dt: float) -> void:
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
		return

	_do_move(dt)

func _do_move(_dt: float) -> void:
	pass

func _update_weak_state() -> void:
	weak = (hp <= weak_hp)
	if weak and weak_stun_t <= 0.0:
		weak_stun_t = weak_stun_time

func _restore_from_weak() -> void:
	hp = max_hp
	weak = false
	weak_stun_t = 0.0

	# 先把要溶解的slot拿出来，然后立刻清空（避免后续逻辑影响）
	var slots: Array[int] = _linked_slots.duplicate()
	_linked_slots.clear()

	# ✅ 把玩家引用缓存到局部变量，随后就算成员被置空也不影响本次
	var p: Node = _linked_player
	_linked_player = null

	if p == null or not is_instance_valid(p):
		return
	if not p.has_method("force_dissolve_chain"):
		return

	for s in slots:
		p.call("force_dissolve_chain", s)

func _find_visual() -> CanvasItem:
	# 1) 显式指定路径（最稳）
	if visual_item_path != NodePath(""):
		var v := get_node_or_null(visual_item_path) as CanvasItem
		if v != null:
			return v

	# 2) 兼容你常用的命名
	var s := get_node_or_null("Sprite2D") as CanvasItem
	if s != null:
		return s
	var vis := get_node_or_null("Visual") as CanvasItem
	if vis != null:
		return vis

	# 3) 自动在子树里找第一个 CanvasItem（适配方块占位：ColorRect/Polygon2D/Sprite2D等）
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
	# 连续受击时：先终止上一次闪烁，避免“看起来没闪/被覆盖”
	if _flash_tw != null:
		_flash_tw.kill()
		_flash_tw = null

	var orig_mod: Color = sprite.modulate
	var orig_self: Color = sprite.self_modulate
	# 提亮：用 HDR 值拉高自发光，避免白色素材“看不出变化”
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
	stunned_t = hit_stun_time
	_update_weak_state()
	if hp <= 0:
		queue_free()

func set_fusion_vanish(v: bool) -> void:
	# 融合时“消失”：禁碰撞+隐藏视觉（可恢复）
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

# 返回：0=普通受击(锁链应溶解)；1=虚弱可链接(锁链进入LINKED)
func on_chain_hit(_player: Node, _chain_index: int) -> int:
	if weak:
		_linked_player = _player
		if not _linked_slots.has(_chain_index):
			_linked_slots.append(_chain_index)
		return 1

	take_damage(1)
	return 0

# Player：锁链链接到怪物时调用
func on_chain_attached(slot: int) -> void:
	if not _linked_slots.has(slot):
		_linked_slots.append(slot)
	if weak:
		weak_stun_t += weak_stun_extend_time

# Player：锁链断裂/溶解/结束时调用
func on_chain_detached(slot: int) -> void:
	_linked_slots.erase(slot)
	# 如果链都没了，就清掉player引用
	if _linked_slots.is_empty():
		_linked_player = null
