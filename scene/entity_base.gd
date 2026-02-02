extends CharacterBody2D
class_name EntityBase

# =============================================================================
# EntityBase - 所有怪物和奇美拉的公共基类
# 功能：属性系统、HP系统、泯灭融合系统、锁链交互、视觉效果
# =============================================================================

# ===== 枚举定义 =====
enum AttributeType { NORMAL = 0, LIGHT = 1, DARK = 2 }
# NORMAL=无属性, LIGHT=光属性, DARK=暗属性

enum SizeTier { SMALL = 0, MEDIUM = 1, LARGE = 2 }
# SMALL=小型, MEDIUM=中型, LARGE=大型（影响融合结果和治愈精灵数量）

enum EntityType { MONSTER = 0, CHIMERA = 1 }
# MONSTER=野生怪物, CHIMERA=融合产物

enum FailType { RANDOM = 0, HOSTILE = 1, VANISH = 2, EXPLODE = 3 }
# 融合失败时的结果类型

# =============================================================================
# 核心属性（在Inspector中设置）
# =============================================================================
@export var attribute_type: AttributeType = AttributeType.NORMAL
# 实体属性：影响融合规则（光+暗=冲突）

@export var size_tier: SizeTier = SizeTier.SMALL
# 实体型号：影响融合时谁存活/消失

@export var species_id: StringName = &""
# 物种ID：用于融合规则匹配（同species_id无法融合）

@export var entity_type: EntityType = EntityType.MONSTER
# 实体类型：怪物或奇美拉

# =============================================================================
# 融合失败设置
# =============================================================================
@export var fusion_fail_type: FailType = FailType.RANDOM
# 当融合失败时的结果类型：
# - RANDOM: 随机选择（怪物+怪物随机HOSTILE/VANISH，奇美拉+奇美拉可能EXPLODE）
# - HOSTILE: 生成敌对怪物（无虚弱状态，可用锁链杀死获得治愈精灵）
# - VANISH: 双方泯灭，生成治愈精灵（小1/中2/大3只）
# - EXPLODE: 爆炸+烂泥（仅奇美拉+奇美拉可能触发）

@export var fusion_damage_percent: float = 0.15
# 光暗冲突且型号不同时，大型怪物损失的HP百分比(0.0~1.0)

# =============================================================================
# HP系统
# =============================================================================
@export var has_hp: bool = true
# 是否拥有HP系统（false=无法被攻击，如某些环境物体）

@export var max_hp: int = 3
# 最大生命值

@export var weak_hp: int = 1
# 当HP≤此值时进入虚弱状态

var hp: int = 3
# 当前生命值（运行时）

var weak: bool = false
# 是否处于虚弱状态（运行时）

var hp_locked: bool = false
# 虚弱时HP锁定，普通攻击无法减少HP（只有泯灭性融合能杀死）

# =============================================================================
# 泯灭融合系统（核心新机制）
# =============================================================================
@export var vanish_fusion_required: int = 1
# 【可配置】虚弱期间需要承受多少次"泯灭性融合"才会真正死亡
# 每只怪物可以设置不同的值：
# - 1: 一次融合就死（默认）
# - 2: 需要两次融合才会死
# - 3: 需要三次融合才会死
# 以此类推...

var vanish_fusion_count: int = 0
# 当前已承受的泯灭性融合次数（运行时计数）

# =============================================================================
# 链接状态
# =============================================================================
var _linked_slot: int = -1
# 被哪条锁链链接（-1=未链接, 0=链0, 1=链1）

var _linked_player: Node = null
# 链接到的玩家引用

@onready var _hurtbox: Area2D = get_node_or_null("Hurtbox") as Area2D
# 受击判定区域

var _hurtbox_original_layer: int = -1
# 保存原始碰撞层（链接时禁用，断链时恢复）

# =============================================================================
# 视觉效果
# =============================================================================
@export var visual_item_path: NodePath = NodePath("")
# 视觉节点路径（用于闪白效果）

@export var ui_icon: Texture2D = null
# UI显示用的图标

@export var flash_time: float = 0.2
# 闪白效果持续时间(秒)

@onready var sprite: CanvasItem = _find_visual()
# 视觉节点引用

var _flash_tw: Tween = null
# 闪白动画Tween

var _original_modulate: Color = Color.WHITE
# 原始modulate颜色（初始化时保存）

var _original_self_modulate: Color = Color.WHITE
# 原始self_modulate颜色（初始化时保存）

var _colors_saved: bool = false
# 是否已保存原始颜色

# =============================================================================
# 生命周期
# =============================================================================
func _ready() -> void:
	hp = max_hp
	_update_weak_state()
	# 保存原始颜色（延迟一帧确保sprite已初始化）
	call_deferred("_save_original_colors")

# =============================================================================
# HP与伤害
# =============================================================================
func take_damage(amount: int) -> void:
	# 受到普通伤害
	# 如果处于虚弱状态且HP锁定，只会闪白不会掉血
	if not has_hp or hp <= 0:
		return
	if hp_locked:
		_flash_once()
		return
	hp = max(hp - amount, 0)
	_flash_once()
	_update_weak_state()
	if hp <= 0 and not hp_locked:
		_on_death()

func _update_weak_state() -> void:
	# 更新虚弱状态
	var was_weak := weak
	weak = has_hp and (hp <= weak_hp) and hp > 0
	if weak and not was_weak:
		# 刚进入虚弱：锁定HP，重置泯灭计数
		hp_locked = true
		vanish_fusion_count = 0

func _on_death() -> void:
	# 死亡处理
	queue_free()

func heal(amount: int) -> void:
	# 治疗
	if not has_hp:
		return
	hp = min(hp + amount, max_hp)
	if hp > weak_hp:
		# 脱离虚弱状态
		weak = false
		hp_locked = false
		vanish_fusion_count = 0

func heal_percent(percent: float) -> void:
	# 按百分比治疗
	heal(int(ceil(float(max_hp) * percent)))

# =============================================================================
# 眩晕状态（基类默认返回false，子类MonsterBase重写）
# =============================================================================
func is_stunned() -> bool:
	# 基类EntityBase没有眩晕状态，默认返回false
	# MonsterBase会重写此方法返回stunned_t > 0.0
	return false

# =============================================================================
# 泯灭融合系统
# =============================================================================
func apply_vanish_fusion() -> bool:
	# 对虚弱状态的实体施加一次泯灭性融合
	# 返回值：
	#   true = 达到泯灭阈值，实体应该死亡
	#   false = 未达到阈值，实体继续存活
	if not weak:
		return false
	
	vanish_fusion_count += 1
	print("[%s] 泯灭融合 %d/%d" % [name, vanish_fusion_count, vanish_fusion_required])
	
	if vanish_fusion_count >= vanish_fusion_required:
		return true  # 达到阈值，应该死亡
	return false  # 未达到阈值，继续存活

func get_vanish_progress() -> float:
	# 获取泯灭进度(0.0~1.0)，用于UI显示
	if vanish_fusion_required <= 0:
		return 1.0
	return float(vanish_fusion_count) / float(vanish_fusion_required)

func get_vanish_remaining() -> int:
	# 获取剩余需要的泯灭次数
	return max(vanish_fusion_required - vanish_fusion_count, 0)

func reset_vanish_count() -> void:
	# 重置泯灭计数（例如从虚弱恢复时）
	vanish_fusion_count = 0

# =============================================================================
# 锁链交互
# =============================================================================
func on_chain_hit(_player: Node, _slot: int) -> int:
	# 被锁链命中时调用
	# 返回值：0=普通受击, 1=可链接
	return 0

func on_chain_attached(slot: int) -> void:
	# 锁链连接时调用
	_linked_slot = slot
	if _hurtbox != null:
		_hurtbox_original_layer = _hurtbox.collision_layer
		_hurtbox.collision_layer = 0  # 链接后禁用受击判定（穿透）
	_flash_once()

func on_chain_detached(slot: int) -> void:
	# 锁链断开时调用
	if slot == _linked_slot:
		_linked_slot = -1
		_linked_player = null
		if _hurtbox != null and _hurtbox_original_layer >= 0:
			_hurtbox.collision_layer = _hurtbox_original_layer  # 恢复受击判定

func is_linked() -> bool:
	# 是否被链接
	return _linked_slot >= 0

func get_linked_slot() -> int:
	# 获取链接的槽位
	return _linked_slot

func is_occupied_by_other_chain(requesting_slot: int) -> bool:
	# 是否已被其他锁链占用
	return _linked_slot >= 0 and _linked_slot != requesting_slot

# =============================================================================
# 视觉效果
# =============================================================================
func _find_visual() -> CanvasItem:
	# 查找视觉节点
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
	for ch in get_children():
		var ci := ch as CanvasItem
		if ci != null:
			return ci
	return null

func _save_original_colors() -> void:
	# 保存原始颜色（只保存一次）
	if _colors_saved:
		return
	if sprite == null:
		sprite = _find_visual()
	if sprite != null:
		_original_modulate = sprite.modulate
		_original_self_modulate = sprite.self_modulate
		_colors_saved = true

func _flash_once() -> void:
	# 播放一次闪白效果
	if sprite == null:
		return
	
	# 确保已保存原始颜色
	if not _colors_saved:
		_save_original_colors()
	
	# 停止之前的闪白
	if _flash_tw != null:
		_flash_tw.kill()
		_flash_tw = null
	
	# 设置高亮
	sprite.modulate = Color(1.0, 1.0, 1.0, _original_modulate.a)
	sprite.self_modulate = Color(1.8, 1.8, 1.8, _original_self_modulate.a)
	
	# Tween回到原始颜色
	_flash_tw = create_tween()
	_flash_tw.tween_property(sprite, "modulate", _original_modulate, flash_time)
	_flash_tw.parallel().tween_property(sprite, "self_modulate", _original_self_modulate, flash_time)

# =============================================================================
# Getter方法
# =============================================================================
func get_ui_icon() -> Texture2D:
	# 获取UI图标
	return ui_icon

func get_attribute_type() -> int:
	# 获取属性类型
	return attribute_type

func get_weak_state() -> bool:
	# 获取虚弱状态
	return weak

func get_icon_id() -> int:
	# 获取图标ID（用于UI显示）
	return attribute_type
