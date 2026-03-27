class_name ItemData
extends Resource

## 背包道具数据定义（Resource 子类）
## 每种道具对应一个 .tres 文件，由 InventoryManager 引用

enum ItemCategory {
	HEAL,             # 恢复 HP
	HEALING_SPRITE,   # 治愈精灵相关增益
	PUZZLE_PROP,      # 场景部署道具（解密用）
	ATTACK_MAGIC,     # 一次性攻击魔法
	CHIMERA_CAPSULE,  # 小型奇美拉容器
	KEY_ITEM,         # 关键任务道具（不可消耗）
}

enum TargetMode {
	SELF,    # 对自身生效
	GROUND,  # 在脚下/前方放置
	NONE,    # 无目标（如关键道具查看）
}

@export var id: StringName = &""
@export var display_name: String = ""
@export var desc_short: String = ""
@export var icon: Texture2D = null
@export var category: ItemCategory = ItemCategory.HEAL
@export var max_stack: int = 1
@export var cooldown_sec: float = 0.0
@export var usable_in_combat: bool = true
@export var target_mode: TargetMode = TargetMode.SELF
@export var consume_on_use: bool = true

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
