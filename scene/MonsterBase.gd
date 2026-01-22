extends CharacterBody2D
class_name MonsterBase
# Godot 4.5
# 基础怪物：掉血 -> 受击闪白 + 僵直 -> HP==1 进入 weak（虚弱）状态
# 约定：
# - Player 的锁链命中时会 call: on_chain_hit(player, slot, hit_world) -> int
#   返回 1：表示允许 Player 进入 LINKED（用于虚弱怪物/奇美拉互动）
#   返回 0：表示普通受击，Player 锁链立刻溶解

enum MonsterKind { FLY, WALK, FLY2, WALK2 }

@export var kind: MonsterKind = MonsterKind.WALK    # 怪物类型（用于组合奇美拉）
@export var max_hp: int = 5                         # 最大HP（MonsterFly=3, MonsterWalk=5）
@export var hit_stun_time: float = 0.1              # 受击僵直时长
@export var weak: bool = false                      # 是否虚弱（HP==1 时 true）
@export var flash_white_time: float = 0.08          # “变亮/变白”持续时间（不是消失）

# 你可以把 Sprite2D/AnimatedSprite2D/Polygon2D 都拖到这里
@export var visual_path: NodePath = ^"Visual"

var hp: int = 5
var _stun_t: float = 0.0
var _visual: CanvasItem = null

func _ready() -> void:
	hp = max_hp
	_visual = get_node_or_null(visual_path) as CanvasItem
	add_to_group("monster")

func _physics_process(dt: float) -> void:
	if _stun_t > 0.0:
		_stun_t -= dt

func is_stunned() -> bool:
	return _stun_t > 0.0

func set_fusion_vanish(v: bool) -> void:
	# 融合演出用：隐藏并禁碰撞（注意：如果你需要恢复原层/Mask，可再扩展缓存）
	visible = not v
	if v:
		collision_layer = 0
		collision_mask = 0

# Player 锁链命中
func on_chain_hit(_player: Node, _slot: int, _hit_world: Vector2) -> int:
	# 虚弱：允许链接（Player 进入 LINKED，不溶解）
	if weak:
		return 1

	# 普通：扣血 + 闪白 + 僵直
	hp = max(hp - 1, 0)
	_stun_t = hit_stun_time
	_flash_white()

	if hp <= 1:
		weak = true
	return 0

func _flash_white() -> void:
	if _visual == null:
		return

	# 变亮：直接 modulate 拉高到接近白
	var orig: Color = _visual.modulate
	_visual.modulate = Color(1, 1, 1, 1)

	var tw := create_tween()
	tw.tween_interval(flash_white_time)
	tw.tween_callback(func() -> void:
		if is_instance_valid(_visual):
			_visual.modulate = orig
	)
