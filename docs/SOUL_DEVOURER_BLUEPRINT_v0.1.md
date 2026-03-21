# 《噬魂犬（Soul Devourer）工程蓝图 v0.1》

> 目标：把需求整理为 **AI 可直接执行** 的工程规范（Godot 4.5 + GDScript + Beehave）。
> 说明：本蓝图严格对齐当前项目硬规则（Monster / ghost / chain / visibility / Beehave / EventBus / Spine）。
> 状态：**第一版框架指引，后续根据实际开发补充细节。**

---

## 0. 名词归一

| 需求原词 | 工程标准名 | 备注 |
|---|---|---|
| 噬魂犬 | `SoulDevourer`（class_name） | 场景文件：`scene/enemies/soul_devourer/SoulDevourer.tscn` |
| 双头噬魂犬 | `TwoHeadedSoulDevourer`（class_name） | 场景文件：`scene/enemies/soul_devourer/TwoHeadedSoulDevourer.tscn` |
| 合体 | `merge` | 两只噬魂犬在漂浮隐身状态下接触后触发 |
| 分离 | `split` | 双头犬攻击结束后还原两只噬魂犬 |
| 漂浮隐身 | `_is_floating_invisible` | 噬魂犬的悬浮隐身态 |
| 双向光炮 | `dual_beam` | 双头犬落地后的必杀技 |
| 游荡幽灵 | `WanderingGhost` | 噬魂犬的猎物 |

---

## 1. 与当前项目硬规则的对齐约束

1. **实体类型为 Monster**：`entity_type = EntityType.MONSTER`，继承 `MonsterBase`。
2. **Beehave 条件节点无副作用，动作节点才执行行为**。
3. **新增事件必须通过 EventBus `emit_*` 封装发出**，禁止直接 `.emit()`。
4. **Spine API 调用必须 `has_method()` 探测兼容 snake_case / camelCase**。
5. **信号 + 轮询双保险**：不允许状态机只靠 Spine 信号推进。
6. **动画切换禁止 `clear_track()`**：直接使用 `set_animation()` 替换。
7. **攻击判定由 Spine 动画事件驱动**：`atk_hit_on` / `atk_hit_off` 控制 hitbox 启闭，禁止纯定时器。
8. **双头噬魂犬是独立场景**：不是噬魂犬的动画变体，而是单独的 SpineSprite 实例和场景。
9. **合体/分离不走 FusionRegistry**：这是噬魂犬的行为逻辑，不是锁链融合系统。

---

## 2. 基础信息

### 2.1 噬魂犬（SoulDevourer）

| 字段 | 值 |
|------|-----|
| 名称 | 噬魂犬 |
| 代码名 | `SoulDevourer` |
| 脚本文件 | `scene/enemies/soul_devourer/soul_devourer.gd` |
| 场景文件 | `scene/enemies/soul_devourer/SoulDevourer.tscn` |
| 类型 | 怪物（Monster） |
| 属性 | DARK |
| 体型 | SMALL |
| 物种ID | `soul_devourer` |
| 移动方式 | 地面行走 + 漂浮隐身 |
| 移动速度 | 待定（地面）/ 待定（漂浮） |
| HP | 待定 |
| 虚弱阈值 | 待定 |
| 材质节点 | SpineSprite |

### 2.2 双头噬魂犬（TwoHeadedSoulDevourer）

| 字段 | 值 |
|------|-----|
| 名称 | 双头噬魂犬 |
| 代码名 | `TwoHeadedSoulDevourer` |
| 脚本文件 | `scene/enemies/soul_devourer/two_headed_soul_devourer.gd` |
| 场景文件 | `scene/enemies/soul_devourer/TwoHeadedSoulDevourer.tscn` |
| 类型 | 特殊实体（不继承 MonsterBase） |
| 属性 | — |
| 物种ID | `two_headed_soul_devourer` |
| 移动方式 | 空中下坠 |
| HP | 无（无敌，不可被伤害） |
| 材质节点 | SpineSprite |

---

## 3. 场景节点树

### 3.1 噬魂犬

```
SoulDevourer (CharacterBody2D)
├── SpineSprite                    # Spine 动画渲染
├── CollisionShape2D               # 身体碰撞体（EnemyBody）
├── Hurtbox (Area2D)               # 受击检测
│   └── CollisionShape2D
├── DetectArea (Area2D)            # 幽灵/玩家检测范围
│   └── CollisionShape2D
├── AttackHitbox (Area2D)          # 攻击判定（由 Spine 事件启闭）
│   └── CollisionShape2D
├── MergeDetectArea (Area2D)       # 合体检测（检测另一只噬魂犬）
│   └── CollisionShape2D
└── BeehaveTree                    # 行为树根节点
```

### 3.2 双头噬魂犬

```
TwoHeadedSoulDevourer (CharacterBody2D)
├── SpineSprite                    # Spine 动画渲染
├── CollisionShape2D               # 身体碰撞体
├── DualBeamHitboxLeft (Area2D)    # 左侧光炮判定
│   └── CollisionShape2D
├── DualBeamHitboxRight (Area2D)   # 右侧光炮判定
│   └── CollisionShape2D
├── SplitMarkLeft (Marker2D)       # 分离后左侧噬魂犬生成点
├── SplitMarkRight (Marker2D)      # 分离后右侧噬魂犬生成点
└── RaycastGround (RayCast2D)      # 地面检测（用于 fall_loop → 落地判定）
```

---

## 4. 碰撞层配置

### 4.1 噬魂犬

```gdscript
# === CharacterBody2D (SoulDevourer) ===
collision_layer = 4   # EnemyBody(3) / Inspector 第3层
collision_mask = 1     # World(1) / Inspector 第1层

# === Hurtbox (Area2D) ===
collision_layer = 8   # EnemyHurtbox(4) / Inspector 第4层
collision_mask = 0     # 不检测任何层

# === DetectArea (Area2D) — 幽灵/玩家检测 ===
collision_layer = 0
collision_mask = 2 | 4  # PlayerBody(2) + EnemyBody(3) / Inspector 第2+3层

# === AttackHitbox (Area2D) ===
collision_layer = 32   # hazards(6) / Inspector 第6层
collision_mask = 2     # PlayerBody(2) / Inspector 第2层

# === MergeDetectArea (Area2D) — 合体检测 ===
collision_layer = 0
collision_mask = 4     # EnemyBody(3) / Inspector 第3层
# 注：通过脚本过滤，只响应另一只 SoulDevourer
```

### 4.2 双头噬魂犬

```gdscript
# === CharacterBody2D (TwoHeadedSoulDevourer) ===
collision_layer = 4   # EnemyBody(3) / Inspector 第3层
collision_mask = 1     # World(1) / Inspector 第1层

# === DualBeamHitboxLeft / Right (Area2D) ===
collision_layer = 32   # hazards(6) / Inspector 第6层
collision_mask = 2     # PlayerBody(2) / Inspector 第2层
```

---

## 5. 噬魂犬核心行为

### 5.1 正常态（地面行走）

- 常规巡逻/待机行为（待细化）
- 可被玩家攻击、受伤、进入虚弱态
- 可被锁链命中（待定是否参与 chain 系统）

### 5.2 漂浮隐身态

- 触发条件：待定（可能是特定行为或状态转换）
- 设置 `_is_floating_invisible = true`
- 身体碰撞层清零（不可被物理碰撞命中）
- Hurtbox 关闭（不可受击）
- 可穿越地形

### 5.3 猎杀幽灵

当 DetectArea 检测到 `WanderingGhost` 时：

1. 朝幽灵位置移动
2. 到达幽灵位置后调用 `ghost.start_being_hunted()`
3. 播放吞食动画
4. 幽灵播放 `hunted` 动画后 `queue_free()`

---

## 6. 合体机制（核心机制）

### 6.1 触发条件

- 场上恰好有 **2 只** 噬魂犬
- **两只都处于漂浮隐身状态**（`_is_floating_invisible == true`）
- 满足以上条件后，两只噬魂犬进入合体行为

### 6.2 合体流程

```
[噬魂犬A 漂浮隐身] + [噬魂犬B 漂浮隐身]
        │                    │
        └──── 向对方移动 ────┘
                  │
         [二者接触（MergeDetectArea 触发）]
                  │
         [记录合体前双方 HP 数据]
                  │
         [二者 queue_free()]
                  │
    [在接触点生成 TwoHeadedSoulDevourer]
                  │
         [播放 enter 动画]
                  │
         [播放 fall_loop 动画（空中下坠）]
                  │
         [RaycastGround 检测到地面]
                  │
         [播放 land 落地动画]
                  │
         [无敌状态 — 不可被玩家伤害]
                  │
         [立即发射 dual_beam（双向光炮）]
                  │
         [范围内玩家受到伤害]
                  │
         [播放 split 分离动画]
                  │
         [动画结尾：在 SplitMarkLeft / SplitMarkRight 还原两只噬魂犬]
                  │
         [两只噬魂犬强制互相远离 200px]
                  │
         [恢复正常逻辑]
```

### 6.3 HP 数据传递

```gdscript
# 合体时记录：
var saved_hp_data: Array = [
    { "hp": dog_a.hp, "max_hp": dog_a.max_hp, "weak_hp": dog_a.weak_hp },
    { "hp": dog_b.hp, "max_hp": dog_b.max_hp, "weak_hp": dog_b.weak_hp },
]

# 分离时还原：
# dog_a 恢复 saved_hp_data[0] 的 HP
# dog_b 恢复 saved_hp_data[1] 的 HP
```

### 6.4 合体协调机制

> 两只噬魂犬需要一个协调者来判断"场上是否有 2 只且都漂浮隐身"。

**方案**：使用 `"soul_devourer"` 组 + 组查询

```gdscript
# 每只噬魂犬在 _ready() 时加入组
add_to_group("soul_devourer")

# 进入漂浮隐身态后检查合体条件
func _check_merge_condition() -> bool:
    var all_devourers: Array = get_tree().get_nodes_in_group("soul_devourer")
    if all_devourers.size() != 2:
        return false
    for d in all_devourers:
        if not d._is_floating_invisible:
            return false
    return true
```

**协调规则**：
- 只由 **实例 ID 较小的那只** 发起合体判定，避免两只同时发起冲突
- 发起者设置双方 `_merging = true`，双方同时开始向对方移动

### 6.5 接触判定

- 使用 `MergeDetectArea`（Area2D）检测
- 当 `area_entered` 信号触发且对方是 `SoulDevourer` 且 `_merging == true` 时：
  - 只由发起者（实例 ID 较小者）执行生成逻辑
  - 计算接触点（两者位置中点）
  - 生成 `TwoHeadedSoulDevourer` 场景
  - 传递双方 HP 数据
  - 双方 `queue_free()`

---

## 7. 双头噬魂犬行为（TwoHeadedSoulDevourer）

### 7.1 生命周期（无行为树，纯脚本状态机）

双头噬魂犬是临时实体，行为固定，不使用 Beehave：

```
ENTER → FALL → LAND → ATTACK → SPLIT → END
```

| 状态 | 动画 | 说明 |
|------|------|------|
| `ENTER` | `enter`（非循环） | 合体出现动画 |
| `FALL` | `fall_loop`（循环） | 空中下坠，RayCast2D 检测地面 |
| `LAND` | `land`（非循环） | 落地动画 |
| `ATTACK` | `dual_beam`（非循环） | 双向光炮攻击；Spine 事件 `atk_hit_on` / `atk_hit_off` 控制 hitbox |
| `SPLIT` | `split`（非循环） | 分离动画；动画结尾生成两只噬魂犬 |

### 7.2 无敌机制

- 落地后（`LAND` 状态开始）到分离完成（`SPLIT` 结束），全程无敌
- 不设置 Hurtbox
- `collision_layer` 不包含 `EnemyHurtbox(4)`
- 如果被 chain 命中：`on_chain_hit()` 返回 0（穿透）

### 7.3 双向光炮（dual_beam）

- 落地后立即执行
- 向左右两侧各发射一道光炮
- 使用 `DualBeamHitboxLeft` 和 `DualBeamHitboxRight` 进行伤害判定
- Hitbox 启闭由 Spine 事件 `atk_hit_on` / `atk_hit_off` 驱动
- 范围内玩家受到伤害（伤害值待定）

### 7.4 分离流程

1. `dual_beam` 动画结束后，播放 `split` 动画
2. `split` 动画完成时：
   - 在 `SplitMarkLeft` 位置实例化噬魂犬 A
   - 在 `SplitMarkRight` 位置实例化噬魂犬 B
   - 还原各自合体前的 HP 数据
   - 设置两只犬的强制分离标记 `_force_separate = true`
3. 两只噬魂犬强制执行移动行为：
   - 各自向外移动，直到相互距离 ≥ 200px
   - 分离完成后 `_force_separate = false`，恢复正常行为逻辑
4. 双头噬魂犬 `queue_free()`

---

## 8. 噬魂犬行为树设计（Beehave）

```
BeehaveTree (process_thread: PHYSICS)
└── SelectorReactiveComposite                       # 最外层响应式选择
    │
    ├── SequenceComposite [死亡锁定]                  # 优先级最高
    │   ├── ConditionLeaf: cond_dying
    │   └── ActionLeaf: act_wait_death
    │
    ├── SequenceComposite [强制分离]                  # 优先级 2
    │   ├── ConditionLeaf: cond_force_separate
    │   └── ActionLeaf: act_separate_move             # 远离另一只犬至 200px
    │
    ├── SequenceComposite [合体移动]                  # 优先级 3
    │   ├── ConditionLeaf: cond_merging
    │   └── ActionLeaf: act_move_to_partner            # 向另一只犬移动
    │
    ├── SequenceComposite [漂浮隐身 — 检查合体]       # 优先级 4
    │   ├── ConditionLeaf: cond_floating_invisible
    │   └── ActionLeaf: act_check_and_start_merge      # 检查合体条件，满足则切换到 merging
    │
    ├── SequenceComposite [猎杀幽灵]                  # 优先级 5
    │   ├── ConditionLeaf: cond_ghost_in_range
    │   └── SequenceComposite
    │       ├── ActionLeaf: act_chase_ghost
    │       └── ActionLeaf: act_devour_ghost
    │
    ├── SequenceComposite [常规行为]                  # 优先级 6
    │   └── ActionLeaf: act_patrol                     # 巡逻/待机
    │
    └── ActionLeaf: act_idle                          # 兜底
```

---

## 9. Spine 动画清单

### 9.1 噬魂犬

| 动画名 | 循环 | 轨道 | 说明 |
|--------|------|------|------|
| `idle` | 是 | 0 | 待机 |
| `walk` | 是 | 0 | 地面行走 |
| `float_idle` | 是 | 0 | 漂浮隐身待机 |
| `float_move` | 是 | 0 | 漂浮隐身移动 |
| `devour` | 否 | 0 | 吞食幽灵 |
| `hit` | 否 | 0 | 受击 |
| `death` | 否 | 0 | 死亡 |
| `weak_loop` | 是 | 0 | 虚弱循环 |

### 9.2 双头噬魂犬

| 动画名 | 循环 | 轨道 | 说明 |
|--------|------|------|------|
| `enter` | 否 | 0 | 合体出现 |
| `fall_loop` | 是 | 0 | 空中下坠循环 |
| `land` | 否 | 0 | 落地 |
| `dual_beam` | 否 | 0 | 双向光炮攻击；含 `atk_hit_on` / `atk_hit_off` 事件 |
| `split` | 否 | 0 | 分离动画 |

### 9.3 Spine 事件

| 事件名 | 所在动画 | 所属实体 | 作用 |
|--------|---------|---------|------|
| `atk_hit_on` | `dual_beam` | TwoHeadedSoulDevourer | 启用双向光炮 Hitbox |
| `atk_hit_off` | `dual_beam` | TwoHeadedSoulDevourer | 禁用双向光炮 Hitbox |

---

## 10. 关键参数（@export 导出）

### 10.1 噬魂犬

```gdscript
@export var walk_speed: float = 100.0          # 地面移动速度(像素/秒)
@export var float_speed: float = 120.0         # 漂浮移动速度(像素/秒)
@export var merge_move_speed: float = 150.0    # 合体时向对方移动速度(像素/秒)
@export var separate_distance: float = 200.0   # 分离后最小间距(像素)
@export var separate_speed: float = 120.0      # 强制分离移动速度(像素/秒)
```

### 10.2 双头噬魂犬

```gdscript
@export var fall_speed: float = 300.0          # 下坠速度(像素/秒)
@export var dual_beam_damage: int = 1          # 光炮伤害值
```

---

## 11. 已确认决策

1. 双头噬魂犬是独立场景和 SpineSprite 实例，不是噬魂犬的动画状态。
2. 合体/分离不走 FusionRegistry 系统，是噬魂犬自身的行为逻辑。
3. 合体触发条件：场上恰好 2 只噬魂犬 + 两只都在漂浮隐身态。
4. 合体协调：实例 ID 较小者发起，避免冲突。
5. 双头犬全程无敌，不可被玩家伤害。
6. 双头犬落地后立即发射双向光炮。
7. 攻击结束后播放分离动画，在 Marker2D 位置还原两只噬魂犬。
8. 还原后恢复合体前各自的 HP 数据。
9. 还原后强制分离至 200px 间距，然后恢复正常逻辑。
10. 双头犬不使用 Beehave 行为树，使用纯脚本状态机（行为固定线性）。
11. 猎杀幽灵的接口与 `WanderingGhost` 蓝图一致：调用 `ghost.start_being_hunted()`。

---

## 12. 待定项（需要用户确认）

| 序号 | 待定内容 | 说明 |
|------|---------|------|
| 1 | 噬魂犬 HP / max_hp / weak_hp 具体数值 | 基础战斗数值 |
| 2 | 噬魂犬何时进入漂浮隐身态 | 条件：HP 低于阈值？定时？特定触发？ |
| 3 | 噬魂犬是否参与 chain 系统 | 能否被锁链命中/链接？ |
| 4 | 噬魂犬的攻击方式（非猎杀幽灵时） | 对玩家的攻击行为 |
| 5 | 噬魂犬的属性（暂定 DARK） | 确认是否为暗属性 |
| 6 | 噬魂犬是否参与融合规则（FusionRegistry） | 是否可被锁链捕获后融合？ |
| 7 | 双向光炮的具体范围和伤害值 | 视觉效果和判定范围 |
| 8 | 噬魂犬地面行走时的具体巡逻/攻击行为 | 除猎杀幽灵和合体外的日常行为 |

---

## 13. 参考文件索引

| 参考内容 | 文件 |
|---------|------|
| 幽灵被吞食接口 | `docs/WANDERING_GHOST_BLUEPRINT_v0.1.md §7` |
| 基类 | `scene/monster_base.gd`、`scene/entity_base.gd` |
| Spine API 规范 | `docs/SPINE_GODOT_LATEST_INTEGRATED_STANDARD.md` |
| Beehave API | `docs/BEEHAVE_REFERENCE.md` |
| Beehave 设计指南 | `docs/E_BEEHAVE_ENEMY_DESIGN_GUIDE.md` |
| 碰撞层 | `docs/A_PHYSICS_LAYER_TABLE.md` |
| 硬约束 | `docs/CONSTRAINTS.md` |
