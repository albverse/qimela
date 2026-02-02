# 如何新增怪物/奇美拉

## 概述

本文档详细说明如何在项目中新增一个怪物(Monster)或奇美拉(Chimera)。

---

## 一、新增怪物 (Monster)

### 步骤1：创建场景文件

1. 在Godot中右键 `res://scene/` → **New Scene**
2. 选择 **CharacterBody2D** 作为根节点
3. 命名为 `MonsterXXX`（如 `MonsterIce`）
4. 保存为 `res://scene/MonsterXXX.tscn`

### 步骤2：构建节点结构

```
MonsterXXX (CharacterBody2D)
├── Sprite2D          # 视觉贴图
├── CollisionShape2D  # 物理碰撞体
└── Hurtbox (Area2D)  # 受击检测区域
    └── CollisionShape2D
```

**关键设置：**

| 节点 | 属性 | 值 |
|------|------|-----|
| MonsterXXX | collision_layer | `4` (EnemyBody/第3层) |
| MonsterXXX | collision_mask | `1` (World/第1层) |
| Hurtbox | collision_layer | `8` (EnemyHurtbox/第4层) |
| Hurtbox | collision_mask | `0` |

### 步骤3：创建脚本

在 `res://scene/` 创建 `monster_xxx.gd`：

```gdscript
extends MonsterBase
class_name MonsterXXX

# ===== 可选：重写移动行为 =====
@export var move_speed: float = 70.0
@export var gravity: float = 1200.0

func _ready() -> void:
    # 【必填】设置物种ID（用于融合规则匹配）
    species_id = &"xxx_attribute"  # 格式: 名称_属性
    
    # 【必填】设置属性类型
    # NORMAL=无属性, LIGHT=光, DARK=暗
    attribute_type = AttributeType.LIGHT
    
    # 【必填】设置型号
    # SMALL=小, MEDIUM=中, LARGE=大
    size_tier = SizeTier.SMALL
    
    # 【可选】设置HP相关
    max_hp = 3
    weak_hp = 1  # HP<=此值时进入虚弱
    
    # 【可选】设置UI图标
    if ui_icon == null:
        ui_icon = preload("res://your_icon.png")
    
    super._ready()

func _do_move(dt: float) -> void:
    # 虚弱时停止移动
    if weak:
        velocity = Vector2.ZERO
        move_and_slide()
        return
    
    # 你的移动逻辑
    velocity.y += gravity * dt
    # ...
    move_and_slide()
```

### 步骤4：挂载脚本到场景

1. 选中场景根节点 `MonsterXXX`
2. 在Inspector中点击 **Script** → **Load**
3. 选择刚创建的 `monster_xxx.gd`

### 步骤5：添加到测试场景

1. 打开 `res://scene/MainTest.tscn`
2. 拖入 `MonsterXXX.tscn` 或右键 **Instance Child Scene**
3. 调整位置

---

## 二、新增奇美拉 (Chimera)

### 步骤1-2：同怪物步骤

### 步骤3：创建脚本

```gdscript
extends ChimeraBase
class_name ChimeraXXX

func _ready() -> void:
    # 【必填】设置物种ID
    species_id = &"chimera_xxx"
    
    # 【必填】设置属性
    attribute_type = AttributeType.NORMAL
    
    # 【可选】型号
    size_tier = SizeTier.MEDIUM
    
    # 【可选】设置图标
    if ui_icon == null:
        ui_icon = preload("res://your_chimera_icon.png")
    
    # 【可选】奇美拉特有属性
    follow_player_when_linked = true  # 链接时跟随玩家
    can_be_attacked = false           # 是否可被攻击
    is_flying = false                 # 是否飞行
    
    super._ready()

# 【可选】玩家互动效果
func on_player_interact(p: Player) -> void:
    # 例如：回血
    if p.has_method("heal"):
        p.call("heal", 1)
```

---

## 三、添加融合规则

### 位置

`res://autoload/fusion_registry.gd` 中的 `_load_rules()` 函数

### 规则格式

```gdscript
"species_a + species_b": {
    "result_scene": "res://scene/ChimeraXXX.tscn",
    "result_type": FusionResultType.SUCCESS
}
```

**注意：** 键会自动按字母序排列，`a + b` 和 `b + a` 匹配同一规则

### 结果类型说明

| 类型 | 值 | UI显示 | 说明 |
|------|---|--------|------|
| SUCCESS | 0 | ui_yes | 成功融合，生成新奇美拉 |
| FAIL_HOSTILE | 1 | ui_die | 失败，生成敌对怪物 |
| FAIL_VANISH | 2 | ui_die | 失败，双方泯灭 |
| FAIL_EXPLODE | 3 | ui_die | 失败，爆炸 |
| HEAL_LARGE | 4 | ui_die | 大型回血/掉血，小型泯灭 |
| REJECTED | 5 | ui_no | 无规则，无法合成 |
| WEAKEN_BOSS | 6 | ui_die | 削弱Boss |

### 示例：添加新规则

```gdscript
func _load_rules() -> void:
    _rules = {
        # ... 现有规则 ...
        
        # 新增：冰怪 + 火怪 → 奇美拉B
        "ice_light + fire_dark": {
            "result_scene": "res://scene/ChimeraB.tscn",
            "result_type": FusionResultType.SUCCESS
        },
        
        # 新增：两只冰怪 → 失败，生成敌对
        "ice_light + ice_light_b": {
            "result_type": FusionResultType.FAIL_HOSTILE,
            "hostile_scene": "res://scene/MonsterHostile.tscn"
        },
    }
```

---

## 四、属性值参考

### species_id 命名规则

格式：`名称_属性[_变体]`

示例：
- `walk_dark` - 暗属性走怪
- `fly_light` - 光属性飞怪
- `fly_light_b` - 光属性飞怪变体B
- `neutral_small` - 无属性小怪
- `chimera_a` - 奇美拉A

### 碰撞层速查表

| 层名 | 层号 | bitmask |
|------|------|---------|
| World | 1 | 1 |
| PlayerBody | 2 | 2 |
| EnemyBody | 3 | 4 |
| EnemyHurtbox | 4 | 8 |
| ObjectSense | 5 | 16 |
| hazards | 6 | 32 |
| ChainInteract | 7 | 64 |

**公式：** bitmask = 1 << (层号 - 1)

---

## 五、检查清单

- [ ] 场景文件创建并保存
- [ ] 节点结构正确（Sprite2D, CollisionShape2D, Hurtbox）
- [ ] 碰撞层设置正确
- [ ] 脚本继承正确（MonsterBase/ChimeraBase）
- [ ] species_id 设置且唯一
- [ ] attribute_type 设置
- [ ] size_tier 设置
- [ ] ui_icon 设置（可选）
- [ ] 融合规则已添加到 FusionRegistry（如需要）
- [ ] 在测试场景中可正常运行
