# HOWTO_ADD_ENTITY.md（添加新实体教程，2026-02-02更新）

---

## 1. 命名规范（必须遵守）

| 类型 | 规范 | 示例 |
|------|------|------|
| .tscn 文件 | PascalCase | `MonsterNewType.tscn` |
| .gd 文件 | snake_case | `monster_new_type.gd` |
| class_name | PascalCase | `MonsterNewType` |
| species_id | snake_case | `new_type_light` |

---

## 2. 添加新怪物

### Step 1: 创建脚本
```gdscript
# 文件：scene/monster_new_type.gd
extends MonsterBase
class_name MonsterNewType

func _ready() -> void:
    # 必填：物种ID（用于融合规则匹配）
    species_id = &"new_type_light"
    
    # 必填：属性类型
    attribute_type = AttributeType.LIGHT  # NORMAL / LIGHT / DARK
    
    # 必填：型号
    size_tier = SizeTier.SMALL  # SMALL / MEDIUM / LARGE
    
    # 可选：HP设置
    max_hp = 3
    weak_hp = 1
    
    super._ready()

func _do_move(dt: float) -> void:
    # 实现移动逻辑
    if weak:
        velocity = Vector2.ZERO
        move_and_slide()
        return
    
    # 你的移动代码...
    move_and_slide()
```

### Step 2: 创建场景
1. 继承模板：右键 `scene/MonsterTemplate.tscn` → New Inherited Scene
2. 重命名为 `MonsterNewType.tscn`
3. 设置脚本为 `monster_new_type.gd`
4. 设置 ui_icon（拖入贴图）
5. 调整碰撞形状

### Step 3: 更新文档
1. 在 `C_ENTITY_DIRECTORY.md` 添加一行
2. 如果有融合规则，更新 `D_FUSION_RULES.md`

---

## 3. 添加新奇美拉

### Step 1: 创建脚本
```gdscript
# 文件：scene/chimera_new_type.gd
extends ChimeraBase
class_name ChimeraNewType

func _ready() -> void:
    species_id = &"chimera_new_type"
    attribute_type = AttributeType.NORMAL
    size_tier = SizeTier.MEDIUM
    
    super._ready()

func _do_chimera_behavior(dt: float) -> void:
    # 实现奇美拉特有行为
    pass
```

### Step 2: 创建场景
1. 继承模板：右键 `scene/ChimeraTemplate.tscn` → New Inherited Scene
2. 重命名为 `ChimeraNewType.tscn`
3. 设置脚本为 `chimera_new_type.gd`
4. 可选：设置 ui_icon

### Step 3: 添加融合规则
```gdscript
# 在 autoload/fusion_registry.gd 的 _rules 中添加：
"species_a + species_b": {
    # 注释：描述组合和产物
    "result_scene": "res://scene/ChimeraNewType.tscn",
    "result_type": FusionResultType.SUCCESS
},
```

### Step 4: 更新文档
1. 在 `C_ENTITY_DIRECTORY.md` 添加奇美拉条目
2. 在 `D_FUSION_RULES.md` 添加融合规则

---

## 4. 场景节点结构

### 怪物标准结构
```
MonsterNewType (CharacterBody2D)
├── Sprite2D
├── CollisionShape2D
└── Hurtbox (Area2D)
    └── CollisionShape2D
```

### 奇美拉标准结构
```
ChimeraNewType (CharacterBody2D)
├── Sprite2D
├── CollisionShape2D
└── Hurtbox (Area2D)
    └── CollisionShape2D
```

### 攻击型奇美拉（如StoneSnake）
```
ChimeraNewType (CharacterBody2D)
├── Sprite2D
├── CollisionShape2D
├── Hurtbox (Area2D)
│   └── CollisionShape2D
├── AttackTimer (Timer)
└── BulletSpawnPoint (Marker2D)
```

---

## 5. 碰撞层设置

### 怪物/奇美拉本体
```
collision_layer = 4   # EnemyBody(3)
collision_mask = 1    # World(1)
```

### Hurtbox
```
collision_layer = 8   # EnemyHurtbox(4)
collision_mask = 0
```

---

## 6. 检查清单

添加新实体后，确认以下项目：

- [ ] 脚本文件名为 snake_case
- [ ] 场景文件名为 PascalCase
- [ ] species_id 已设置且唯一
- [ ] attribute_type 已设置
- [ ] size_tier 已设置
- [ ] ui_icon 已设置（如果需要显示在UI中）
- [ ] 碰撞层正确
- [ ] C_ENTITY_DIRECTORY.md 已更新
- [ ] D_FUSION_RULES.md 已更新（如果有融合规则）
- [ ] 在测试场景中测试功能

---

## 7. 常见问题

### Q: 怪物不能被锁链命中
检查 Hurtbox 的 collision_layer 是否为 8 (EnemyHurtbox)

### Q: 融合不生效
1. 检查 species_id 是否正确
2. 检查融合规则是否在 fusion_registry.gd 中
3. 检查两个怪物是否都处于 weak/stun 状态

### Q: UI 图标不显示
检查 .tscn 中是否设置了 ui_icon 属性
