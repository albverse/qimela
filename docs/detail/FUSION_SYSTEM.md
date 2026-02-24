# 融合系统 (Fusion System)

> 源文件: `autoload/fusion_registry.gd`

## 概述

`FusionRegistry` 是一个 Autoload 单例，负责管理游戏中所有怪物/奇美拉之间的融合规则。它提供融合可行性检查和融合执行两大核心功能。

---

## 融合结果类型枚举

```gdscript
enum FusionResultType {
    SUCCESS       = 0,  # 成功融合：生成新的奇美拉
    FAIL_HOSTILE  = 1,  # 失败-敌对：生成敌对怪物（无法进入虚弱状态）
    FAIL_VANISH   = 2,  # 失败-泯灭：双方尝试泯灭，生成治愈精灵
    FAIL_EXPLODE  = 3,  # 失败-爆炸：双方爆炸（仅奇美拉+奇美拉）
    HEAL_LARGE    = 4,  # 型号不同：大型实体回血或掉血，小型实体消失
    REJECTED      = 5,  # 拒绝融合：不满足融合条件
    WEAKEN_BOSS   = 6,  # 特殊-削弱Boss：对Boss造成固定百分比伤害
}
```

| 枚举值 | 名称 | 说明 |
|--------|------|------|
| 0 | `SUCCESS` | 成功融合，生成新奇美拉 |
| 1 | `FAIL_HOSTILE` | 失败，生成敌对怪物（无法虚弱） |
| 2 | `FAIL_VANISH` | 失败，双方泯灭，掉落治愈精灵 |
| 3 | `FAIL_EXPLODE` | 失败，双方爆炸+伤害范围内玩家（仅奇美拉间） |
| 4 | `HEAL_LARGE` | 型号不同时，大型实体回血/掉血，小型消失 |
| 5 | `REJECTED` | 拒绝融合（同物种/无规则/不兼容） |
| 6 | `WEAKEN_BOSS` | 对Boss造成固定百分比 HP 伤害 |

---

## 核心 API

### `check_fusion(entity_a, entity_b) -> Dictionary`

检查两个实体是否可以融合，返回结果字典。

**返回字典字段:**

| 字段 | 类型 | 说明 |
|------|------|------|
| `type` | `FusionResultType` | 融合结果类型 |
| `scene` | `String` | 成功时生成的场景路径 |
| `rule` | `Dictionary` | 匹配到的规则数据 |
| `entity_a` | `EntityBase` | 第一个实体引用 |
| `entity_b` | `EntityBase` | 第二个实体引用 |
| `hostile_scene` | `String` | `FAIL_HOSTILE` 时生成的敌对怪物场景 |
| `larger` / `smaller` | `EntityBase` | `HEAL_LARGE` 时的大型/小型实体引用 |
| `reason` | `String` | `REJECTED` 时的拒绝原因 |

**检查流程:**

```
1. 同一实例？            → REJECTED ("same_instance")
2. 同种族 species_id？   → REJECTED ("same_species")
3. 光+暗属性冲突？       → 查表/按型号决定失败类型
4. 有具体融合规则？       → 按规则返回
5. 同属性/含无属性？     → 型号不同回血，型号相同拒绝
6. 以上都不满足          → REJECTED ("incompatible")
```

### `execute_fusion(result, player) -> Node`

执行融合操作，根据 `check_fusion` 返回的结果字典生成对应实体。

**执行流程:**

1. 让两个实体视觉消失（`set_fusion_vanish(true)`）
2. 发出 `fusion_started` 信号
3. 根据 `result.type` 执行对应逻辑
4. 清理应该销毁的实体（`queue_free()`）
5. 发出 `fusion_completed` 信号
6. 返回生成的新实体节点（失败时返回 `null`）

---

## 融合前提条件

融合要求以下条件同时满足：

1. **两个实体都处于虚弱（weak）或眩晕（stunned）状态**
2. **两个实体都被锁链锁定（chain-linked）** -- 即 SlotA 和 SlotB 各绑定一个目标
3. **两个目标必须是不同的实体** -- 同一目标会被 UI 显示为 `UI_NO`

---

## 融合规则表

规则以 `"species_a + species_b"` 为键存储，键自动按字母序排列以确保 A+B 和 B+A 匹配同一规则。

```gdscript
func _make_key(species_a: StringName, species_b: StringName) -> String:
    var a := String(species_a)
    var b := String(species_b)
    if a > b:
        return b + " + " + a
    return a + " + " + b
```

### 当前成功规则 (SUCCESS)

| 规则键 | 组合 | 产物 |
|--------|------|------|
| `fly_light + walk_dark` | 飞怪(光) + 走怪(暗) | `ChimeraA.tscn` |
| `fly_light + neutral_small` | 飞怪(光) + 无属性怪 | `ChimeraA.tscn` |
| `neutral_small + walk_dark` | 无属性怪 + 走怪(暗) | `ChimeraA.tscn` |
| `fly_light + hand_light` | 飞怪(光) + 手怪(光) | `Chimera_StoneSnake.tscn` |

### 当前失败规则 (FAIL_HOSTILE)

| 规则键 | 组合 | 产物 |
|--------|------|------|
| `fly_light + fly_light_b` | 飞怪(光) + 飞怪B(光) | `MonsterHostile.tscn` |
| `walk_dark + walk_dark_b` | 走怪(暗) + 走怪B(暗) | `MonsterHostile.tscn` |

---

## 信号

```gdscript
signal fusion_started(entity_a: Node, entity_b: Node)
signal fusion_completed(result_type: int, result_entity: Node)
signal vanish_progress_updated(entity: Node, current: int, required: int)
```

---

## UI 预测显示

`ChainSlotsUI` 的 `ConnectionLine/CenterIcon` 根据 `check_fusion` 结果显示预测图标：

| 融合结果 | UI 图标 |
|---------|---------|
| `SUCCESS` | `UI_yes`（绿色勾） |
| `REJECTED` | `UI_NO`（红色叉） |
| 其他所有失败类型 | `UI_DIE`（骷髅） |

```gdscript
match result_type:
    FusionRegistry.FusionResultType.SUCCESS:
        center_icon.texture = ui_yes
    FusionRegistry.FusionResultType.REJECTED:
        center_icon.texture = ui_no
    _:
        center_icon.texture = ui_die
```

---

## 单一真相源 (Single Source of Truth)

> `docs/D_FUSION_RULES.md` 与 `autoload/fusion_registry.gd` 必须保持同步。

添加新规则时的步骤：

1. 在 `fusion_registry.gd` 的 `_rules` 字典中添加规则
2. 同步更新 `D_FUSION_RULES.md`
3. 如果涉及新实体，同步更新 `C_ENTITY_DIRECTORY.md`
4. 测试融合是否正常工作

---

## 规则管理 API

```gdscript
func add_rule(species_a: StringName, species_b: StringName, rule: Dictionary) -> void
func remove_rule(species_a: StringName, species_b: StringName) -> void
func has_rule(species_a: StringName, species_b: StringName) -> bool
func get_all_rules() -> Dictionary   # 调试用
func print_all_rules() -> void       # 调试用
```
