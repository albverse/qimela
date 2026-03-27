class_name ItemData
extends Resource

## 背包道具数据定义（Resource 子类）
## 每种道具对应一个 .tres 文件，由 ItemRegistry / PlayerInventory 引用
## v0.2: 双级分类 (MainCategory + SubCategory) + UseType 行为分发

# ── 主分类（强约束） ──
enum MainCategory {
	USABLE,       # 可主动使用
	NON_USABLE,   # 不可主动使用
}

# ── 子分类（强约束） ──
enum SubCategory {
	CONSUMABLE,   # 消耗品（精灵瓶、恢复药剂、一次性攻击魔法）
	KEY_ITEM,     # 重要物品（禁止卖出与丢弃）
	MATERIAL,     # 一般掉落物（可卖钱、可任务交付、不可消耗）
}

# ── 使用类型（行为分发用，与分类解耦） ──
enum UseType {
	NONE,            # 无主动效果（KEY_ITEM / MATERIAL）
	HEAL,            # 恢复 HP
	SUMMON_SPRITE,   # 释放治愈精灵
	ATTACK_MAGIC,    # 一次性攻击魔法
	DEPLOY_PROP,     # 场景部署道具（解密用）
	SUMMON_CHIMERA,  # 小型奇美拉容器
}

# ── 目标模式 ──
enum TargetMode {
	SELF,    # 对自身生效
	GROUND,  # 在脚下/前方放置
	ENEMY,   # 对敌人生效
	NONE,    # 无目标（如关键道具查看）
}

# ── 基础字段 ──
@export var id: StringName = &""
@export var display_name: String = ""
@export var desc_short: String = ""

# ── 分类 ──
@export var main_category: MainCategory = MainCategory.USABLE
@export var sub_category: SubCategory = SubCategory.CONSUMABLE
@export var use_type: UseType = UseType.NONE

# ── 外观（掉落与背包分离） ──
@export var drop_sprite: Texture2D = null       # 场景可拾取形态
@export var inventory_icon: Texture2D = null     # 背包内图标

# ── 通用属性 ──
@export var max_stack: int = 1
@export var cooldown_sec: float = 0.0
@export var usable_in_combat: bool = true
@export var target_mode: TargetMode = TargetMode.SELF
@export var consume_on_use: bool = true

# ── 经济与规则 ──
@export var sell_value: int = 0
@export var can_drop: bool = true
@export var can_sell: bool = true
@export var tags: PackedStringArray = PackedStringArray()

# ── 类别特化参数 ──
@export_group("Heal")
@export var hp_restore: int = 0

@export_group("Attack Magic")
@export var use_scene_path: String = ""  # 实例化的特效/投射物场景

@export_group("Puzzle Prop")
@export var deploy_scene_path: String = ""  # 部署到场景的节点

@export_group("Chimera Capsule")
@export var chimera_species_id: StringName = &""
@export var chimera_scene_path: String = ""
