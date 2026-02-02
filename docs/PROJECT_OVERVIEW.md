# 奇美拉项目文档 (2026-01-27)

> **本文档为项目核心参考，包含所有系统设计与实现状态**

---

## 1. 项目概述

### 1.1 游戏类型
2D横版动作解谜游戏原型

### 1.2 核心机制
- 双锁链投射系统
- 怪物虚弱/链接/融合
- 奇美拉生成与进化

### 1.3 引擎与技术栈
- **引擎**: Godot 4.5
- **语言**: GDScript
- **当前阶段**: 原型开发

---

## 2. 已完成系统

### 2.1 实体类系统 ✅
| 类名 | 继承自 | 用途 |
|------|--------|------|
| EntityBase | CharacterBody2D | 所有可链接实体的基类 |
| MonsterBase | EntityBase | 怪物基类 |
| ChimeraBase | EntityBase | 奇美拉基类 |

### 2.2 融合注册系统 ✅
- **文件**: `autoload/fusion_registry.gd`
- **功能**: 管理所有融合规则、检查融合可行性、执行融合

### 2.3 UI动画系统 ✅ (本次修复)
- **文件**: `ui/chain_slots_ui.gd`
- **特性**: 严格串行动画播放

### 2.4 闪白效果系统 ✅ (本次修复)
- **文件**: `scene/entity_base.gd`
- **特性**: 保存原始颜色，防止多次闪白导致颜色累积

### 2.5 锁链断开恢复 ✅ (本次修复)
- **文件**: `scene/monster_base.gd`
- **特性**: 断链后正确恢复Hurtbox碰撞层

---

## 3. 融合系统详解

### 3.1 融合结果类型
```gdscript
enum FusionResultType {
    SUCCESS = 0,        # 成功融合，生成新奇美拉
    FAIL_VANISH = 1,    # 泯灭：两只怪物都消失
    FAIL_HOSTILE = 2,   # 敌对：生成敌对怪物
    FAIL_EXPLODE = 3,   # 爆炸：范围伤害
    HEAL_LARGE = 4,     # 治愈：大量回复
    WEAKEN_BOSS = 5     # 削弱Boss
}
```

### 3.2 当前融合规则表
| 组合 | 结果 | 产物 |
|------|------|------|
| fly_light + walk_dark | SUCCESS | ChimeraA |
| fly_light + neutral_small | SUCCESS | ChimeraA |
| neutral_small + walk_dark | SUCCESS | ChimeraA |
| fly_light + fly_light_b | FAIL_HOSTILE | MonsterHostile |
| walk_dark + walk_dark_b | FAIL_HOSTILE | MonsterHostile |

### 3.3 UI融合预测图标
| 图标 | 含义 | 触发条件 |
|------|------|----------|
| UI_yes.png | 可融合 | FusionResultType.SUCCESS |
| UI_NO.png | 不可融合 | 无规则/同目标/无法检测 |
| UI_DIE.png | 融合失败 | FAIL_VANISH/FAIL_HOSTILE/FAIL_EXPLODE |

---

## 4. UI动画系统详解

### 4.1 释放动画顺序 (严格串行)
```
1. AnimationPlayer倒放动画 → 完成后
2. Burn Shader动画 → 完成后  
3. Cooldown Shader动画
```

### 4.2 无目标释放
- 锁链未绑定任何目标时，释放后立即播放Cooldown Shader
- 无等待时间

### 4.3 关键函数
| 函数 | 用途 |
|------|------|
| `_on_chain_released()` | 处理锁链释放，编排动画序列 |
| `_stop_all_slot_animations()` | 停止所有正在进行的动画 |
| `_setup_burn_shader_on_icon()` | 设置burn shader材质 |
| `_update_burn_progress()` | 更新burn进度 |
| `_clear_monster_icon()` | 清理怪物图标 |

---

## 5. 怪物系统详解

### 5.1 怪物属性类型
```gdscript
enum AttributeType {
    NORMAL = 0,  # 无属性（灰色）
    LIGHT = 1,   # 光属性（白/金色）
    DARK = 2     # 暗属性（黑/紫色）
}
```

### 5.2 当前怪物列表
| 文件 | species_id | 属性 | 颜色 | HP |
|------|------------|------|------|-----|
| MonsterWalk.tscn | walk_dark | DARK | 默认 | 5 |
| MonsterFly.tscn | fly_light | LIGHT | 默认 | 3 |
| MonsterNeutral.tscn | neutral_small | NORMAL | 灰色 | 3 |
| MonsterWalkB.tscn | walk_dark_b | DARK | 紫色 | 4 |
| MonsterFlyB.tscn | fly_light_b | LIGHT | 金色 | 2 |
| MonsterHostile.tscn | hostile_fail | NORMAL | 红色 | 5 |

### 5.3 泯灭融合系统
- `vanish_fusion_required`: 虚弱后需要多少次泯灭融合才会死亡
- `vanish_fusion_count`: 当前泯灭融合计数
- `apply_vanish_fusion()`: 应用一次泯灭融合

---

## 6. 物理碰撞层表

| 层号(Inspector) | 层名 | bitmask | 用途 |
|---:|---|---:|---|
| 1 | World | 1 | 静态地形 |
| 2 | PlayerBody | 2 | 玩家物理实体 |
| 3 | EnemyBody | 4 | 怪物物理实体 |
| 4 | EnemyHurtbox | 8 | 怪物受击检测 |
| 5 | ObjectSense | 16 | 雷花等感知层 |
| 6 | hazards | 32 | 危险区域 |
| 7 | ChainInteract | 64 | 锁链交互层 |

### 换算公式
**第N层 → bitmask = 1 << (N-1)**

---

## 7. 关键代码规范

### 7.1 禁止写法
```gdscript
# ❌ 三目运算符
var x = cond ? A : B

# ❌ Variant类型推断
var n := scene.instantiate()

# ❌ 碰撞层手写数字
collision_mask = 5
```

### 7.2 正确写法
```gdscript
# ✅ if-else表达式
var x = A if cond else B

# ✅ 显式类型转换
var n: Node = (scene as PackedScene).instantiate()

# ✅ 碰撞层带注释
collision_mask = 8  # EnemyHurtbox(4) / Inspector 第4层
```

---

## 8. 文件结构

```
qimela-master/
├── autoload/
│   ├── event_bus.gd          # 事件总线
│   └── fusion_registry.gd    # 融合注册系统
├── scene/
│   ├── entity_base.gd        # 实体基类
│   ├── monster_base.gd       # 怪物基类
│   ├── chimera_base.gd       # 奇美拉基类
│   ├── monster_walk.gd       # 暗属性走怪
│   ├── monster_fly.gd        # 光属性飞怪
│   ├── monster_neutral.gd    # 无属性怪
│   ├── monster_walk_b.gd     # 暗属性走怪B
│   ├── monster_fly_b.gd      # 光属性飞怪B
│   ├── monster_hostile.gd    # 敌对怪物
│   ├── chimera_a.gd          # 奇美拉A
│   └── components/
│       └── player_chain_system.gd  # 锁链系统
├── ui/
│   └── chain_slots_ui.gd     # 锁链槽位UI
└── docs/
    └── PROJECT_OVERVIEW.md   # 本文档
```

---

## 9. 本次更新记录 (2026-01-27)

### 9.1 UI动画系统修复 (v3)
- **问题1**: 锁链未击中目标时，释放动画不正确
- **问题2**: 怪物挣脱时，倒放动画被重复播放（与burn同时）
- **修复**: 
  - 根据挣扎进度(`progress`)计算动画当前位置
  - 只倒放动画的剩余部分，而非整个动画
  - 无目标时立即停止动画并播放cooldown
- **关键改动**: `_on_chain_released()`中添加`current_progress`和`current_anim_pos`计算

### 9.2 奇美拉跟随修复
- **问题**: 奇美拉断链后再次链接，不会再跟随玩家
- **原因**: `ChimeraBase.on_chain_detached()`无条件清空`_player`
- **修复**: 只有当确实断开链接时才清空`_player`
- **文件**: `scene/chimera_base.gd`

### 9.3 闪白系统修复
- **问题**: 多次闪白导致颜色累积无法恢复
- **修复**: 在`_ready()`时保存原始颜色，闪白始终回到原始值

### 9.4 锁链断开恢复修复
- **问题**: 断链后Hurtbox碰撞层未恢复，无法再次绑定
- **修复**: 在`_release_linked_chains()`中添加恢复碰撞层逻辑

### 9.5 新增怪物
- MonsterNeutral (无属性，可与任何属性融合)
- MonsterWalkB (暗属性变体，紫色)
- MonsterFlyB (光属性变体，金色)
- MonsterHostile (融合失败产物，红色)

### 9.6 融合规则扩展
- 添加无属性怪物融合规则
- 添加同属性融合失败规则(FAIL_HOSTILE)

---

## 10. 待完成任务

### 优先级: 高
- [ ] 测试所有融合规则
- [ ] 完善奇美拉行为脚本

### 优先级: 中
- [ ] 添加更多融合规则
- [ ] 创建更多奇美拉类型
- [ ] Boss战机制设计

### 优先级: 低
- [ ] 音效系统
- [ ] 粒子效果
- [ ] 存档系统
