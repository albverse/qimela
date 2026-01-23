extends CharacterBody2D
class_name MonsterBase

@export var max_hp: int = 3
@export var weak_hp: int = 1                 # hp==1 => 虚弱/昏迷
@export var hit_stun_time: float = 0.1       # 受击僵直
@export var flash_time: float = 0.2          # 闪烁时长

# 受击闪白/变亮要作用到哪个“外观节点”（Sprite2D / AnimatedSprite2D / ColorRect 等 CanvasItem）。
# 为空则自动在子树里找第一个 CanvasItem。
@export var visual_item_path: NodePath = NodePath("")

var hp: int = 3
var stunned_t: float = 0.0
var weak: bool = false

@onready var sprite: CanvasItem = _find_visual()
var _flash_tw: Tween = null

func _ready() -> void:
	add_to_group("monster")
	hp = max_hp
	_update_weak_state()

func _physics_process(dt: float) -> void:
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

	var orig: Color = sprite.modulate
	# 变白：直接打到白色（对“用 modulate 着色的白色方块素材”最直观）
	sprite.modulate = Color(1.0, 1.0, 1.0, orig.a)
	_flash_tw = create_tween()
	_flash_tw.tween_property(sprite, "modulate", orig, flash_time)

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
	# 融合时“消失”：不需要真实粒子/物理，先禁碰撞+隐藏视觉即可
	collision_layer = 0 if v else collision_layer
	collision_mask = 0 if v else collision_mask
	var s := get_node_or_null("Sprite2D") as Node
	if s != null and s is CanvasItem:
		(s as CanvasItem).visible = not v

# 返回：0=普通受击(锁链应溶解)；1=虚弱可链接(锁链进入LINKED)
func on_chain_hit(_player: Node, _chain_index: int) -> int:
	# 虚弱：允许链接（不扣血）
	if weak:
		return 1

	# 非虚弱：扣血+闪烁+僵直
	take_damage(1)
	return 0
