# 0_ROUTER.md（主索引，2026-02-02更新）

> **使用方式**：默认只读本文件。触发器命中时才读对应模块文档。

---

## 1. 文档结构

| 文档 | 用途 | 触发器 |
|------|------|--------|
| A_PHYSICS_LAYER_TABLE.md | 碰撞层/bitmask | collision_layer, mask, RayCast, Area2D |
| B_GAMEPLAY_RULES.md | 玩法规则/输入/状态 | 输入, weak, stun, 天气, 雷花 |
| C_ENTITY_DIRECTORY.md | 实体目录（唯一真相） | species_id, attribute, ui_icon |
| D_FUSION_RULES.md | 融合规则（唯一真相） | 融合, fusion, check_fusion |
| HOWTO_ADD_ENTITY.md | 添加新实体教程 | 新怪物, 新奇美拉 |

---

## 2. 功能完成状态

### ✅ 已完成
- 锁链发射/收回/溶解
- 怪物虚弱/眩晕系统
- 融合系统（SUCCESS/REJECTED/FAIL_HOSTILE/FAIL_VANISH）
- 锁链槽位UI（双槽显示、图标、cooldown、融合预览）
- 回血精灵（拾取/环绕/使用）
- 天气系统（雷击/雷花）
- 飞怪显隐系统
- ChimeraA（跟随型）
- ChimeraStoneSnake（攻击型，发射子弹）
- 玩家HP/受击/击退

### 🔧 TODO
- FAIL_HOSTILE 实际生成敌对怪（当前仅打印日志）
- Boss 削弱机制
- 存档系统

---

## 3. 输入映射（唯一真相）

| 功能 | action名 | 按键 |
|------|---------|------|
| 移动左 | move_left | A |
| 移动右 | move_right | D |
| 跳跃 | jump | W |
| 发射锁链 | (无action) | 鼠标左键 |
| 取消锁链 | cancel_chains | X |
| 融合 | fuse | Space |
| 使用回血精灵 | use_healing | C |

---

## 4. 命名规范

| 类型 | 规范 | 示例 |
|------|------|------|
| .tscn 文件 | PascalCase | `MonsterFly.tscn` |
| .gd 文件 | snake_case | `monster_fly.gd` |
| class_name | PascalCase | `MonsterFly` |
| species_id | snake_case | `fly_light` |
| action名 | snake_case | `cancel_chains` |

---

## 5. 关键文件路径

### 核心脚本
```
scene/player.gd              # 玩家主脚本
scene/entity_base.gd         # 实体基类
scene/monster_base.gd        # 怪物基类
scene/chimera_base.gd        # 奇美拉基类
scene/components/player_chain_system.gd  # 锁链系统
```

### Autoload
```
autoload/event_bus.gd        # 事件总线
autoload/fusion_registry.gd  # 融合规则注册表
```

### UI
```
ui/chain_slots_ui.gd         # 锁链槽UI
ui/hearts_ui.gd              # 血量UI
```

---

## 6. 文档读取协议

默认只用本文件回答。需要细节时请求读取：

**格式**：`NEED_DOC: A|B|C|D | 目的: <一句话>`

| 代号 | 文档 |
|------|------|
| A | A_PHYSICS_LAYER_TABLE.md |
| B | B_GAMEPLAY_RULES.md |
| C | C_ENTITY_DIRECTORY.md |
| D | D_FUSION_RULES.md |

---

## 7. Layer/Mask 速查

| 层号 | 层名 | bitmask |
|------|------|---------|
| 1 | World | 1 |
| 2 | PlayerBody | 2 |
| 3 | EnemyBody | 4 |
| 4 | EnemyHurtbox | 8 |
| 5 | ObjectSense | 16 |
| 6 | hazards | 32 |
| 7 | ChainInteract | 64 |

换算：第N层 → bitmask = 1 << (N-1)
