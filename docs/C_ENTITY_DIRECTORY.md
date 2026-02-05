# C_ENTITY_DIRECTORY.md（实体目录表）

> **唯一真相**：所有实体的 species_id / attribute / size / ui_icon 以此表为准。
> 代码中设置必须与此表一致。

---

## 1. 怪物（Monster）

| species_id | 场景文件 | 脚本文件 | attribute | size | ui_icon | 备注 |
|------------|---------|---------|-----------|------|---------|------|
| `fly_light` | MonsterFly.tscn | monster_fly.gd | LIGHT | SMALL | tori.png | 飞怪主体 |
| `fly_light_b` | MonsterFlyB.tscn | monster_fly_b.gd | LIGHT | SMALL | ❌未设置 | 飞怪变体 |
| `walk_dark` | MonsterWalk.tscn | monster_walk.gd | DARK | SMALL | shitou.png | 走怪主体 |
| `walk_dark_b` | MonsterWalkB.tscn | monster_walk_b.gd | DARK | SMALL | ❌未设置 | 走怪变体 |
| `hand_light` | MonsterHand.tscn | monster_hand.gd | LIGHT | SMALL | yure.png | 手怪 |
| `neutral_small` | MonsterNeutral.tscn | monster_neutral.gd | NORMAL | SMALL | ❌未设置 | 无属性怪 |
| `hostile_fail` | MonsterHostile.tscn | monster_hostile.gd | NORMAL | MEDIUM | ❌未设置 | 敌对怪（融合失败产物） |

---

## 2. 奇美拉（Chimera）

| species_id | 场景文件 | 脚本文件 | attribute | size | ui_icon | 备注 |
|------------|---------|---------|-----------|------|---------|------|
| `chimera_a` | ChimeraA.tscn | chimera_a.gd | NORMAL | MEDIUM | ❌未设置 | 基础奇美拉（跟随型） |
| `chimera_stone_snake` | Chimera_StoneSnake.tscn | chimera_stone_snake.gd | NORMAL | MEDIUM | stone_snake.png | 石蛇奇美拉（攻击型） |

---

## 3. 其他实体

| 名称 | 场景文件 | 脚本文件 | 备注 |
|------|---------|---------|------|
| 治愈精灵 | HealingSprite.tscn | healing_sprite.gd | 回血道具，最多携带3只 |
| 雷花 | LightningFlower.tscn | lightning_flower.gd | 环境交互物 |

---

## 4. ui_icon 规范

### 必须设置 ui_icon 的实体
- 所有可被锁链命中的怪物（会显示在锁链槽UI中）
- 所有奇美拉（可选，但建议设置）

### 允许为空的情况
- 测试用怪物（如 MonsterDummy）
- 融合失败产物（如 MonsterHostile，因为不可链接）

### 设置方式
在 .tscn 文件的节点属性中设置：
```
[node name="MonsterXXX" ...]
ui_icon = ExtResource("贴图资源ID")
```

或在 Inspector 中拖入贴图。

---

## 5. species_id 命名规范

格式：`{类型}_{属性}` 或 `{类型}_{属性}_{变体}`

示例：
- `fly_light` - 飞怪，光属性
- `walk_dark_b` - 走怪，暗属性，B变体
- `chimera_stone_snake` - 奇美拉，石蛇

**注意**：同 species_id 的两个实体无法融合（会被 FusionRegistry 自动拒绝）。

---

## 6. 属性类型（AttributeType）

| 值 | 含义 | 融合规则 |
|----|------|---------|
| NORMAL | 无属性 | 可与任何属性融合 |
| LIGHT | 光属性 | 光+光可能触发FAIL_HOSTILE |
| DARK | 暗属性 | 暗+暗可能触发FAIL_HOSTILE |

---

## 7. 型号（SizeTier）

| 值 | 含义 | 说明 |
|----|------|------|
| SMALL | 小型 | 普通怪物 |
| MEDIUM | 中型 | 奇美拉/敌对怪 |
| LARGE | 大型 | Boss（待实现） |

---

## 8. 待补充的 ui_icon（TODO）

以下实体缺少 ui_icon，如果需要显示在UI中，请补充：

- [ ] MonsterFlyB.tscn
- [ ] MonsterWalkB.tscn
- [ ] MonsterNeutral.tscn
- [ ] MonsterHostile.tscn
- [ ] ChimeraA.tscn
