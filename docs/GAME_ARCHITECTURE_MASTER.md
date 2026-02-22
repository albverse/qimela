# 奇美拉（Qimela）— 游戏结构大全总表

> **本文件是 AI 写代码时的首选查阅入口。**
> 按功能模块索引，每个模块有简要说明 + 关键文件 + 详细文档链接。
> 遇到具体实现细节时，转入对应的 `docs/detail/` 子文档。

---

## 0. 项目基本信息

| 项目 | 值 |
|------|-----|
| 项目名 | chain（Godot内部名），文件夹名 qimela |
| 引擎 | Godot 4.5 |
| 语言 | GDScript |
| 阶段 | 原型开发 |
| 类型 | 2D横版动作解谜 |
| 核心 | 双锁链投射 + 怪物虚弱/融合 + 奇美拉生成与进化 |

---

## 1. 功能模块总览

| # | 模块名 | 简述 | 关键文件 | 详细文档 |
|---|--------|------|----------|----------|
| 1 | **玩家系统** | 调度总线 + tick 顺序 + 组件组装 | `scene/player.gd`, `Player.tscn` | [detail/PLAYER_SYSTEM.md](detail/PLAYER_SYSTEM.md) |
| 2 | **移动系统** | 水平移动/重力/跳跃/意图 | `scene/components/player_movement.gd` | [detail/PLAYER_SYSTEM.md](detail/PLAYER_SYSTEM.md) |
| 3 | **移动状态机** | Idle/Walk/Run/Jump 状态切换 | `scene/components/player_locomotion_fsm.gd` | [detail/PLAYER_SYSTEM.md](detail/PLAYER_SYSTEM.md) |
| 4 | **动作状态机** | None/Attack/AttackCancel/Fuse/Hurt/Die | `scene/components/player_action_fsm.gd` | [detail/PLAYER_SYSTEM.md](detail/PLAYER_SYSTEM.md) |
| 5 | **锁链系统** | 双槽 Verlet 绳索 + 发射/链接/溶解 | `scene/components/player_chain_system.gd` | [detail/CHAIN_SYSTEM.md](detail/CHAIN_SYSTEM.md) |
| 6 | **武器系统** | Chain/Sword/Knife 切换 + 动画委托 | `scene/components/weapon_controller.gd` | [detail/WEAPON_SYSTEM.md](detail/WEAPON_SYSTEM.md) |
| 7 | **动画系统** | 双轨道 Animator + Spine/Mock 驱动 | `scene/components/player_animator.gd`, `anim_driver_spine.gd`, `anim_driver_mock.gd` | [detail/ANIMATION_SYSTEM.md](detail/ANIMATION_SYSTEM.md) |
| 8 | **生命系统** | HP/无敌帧/击退/伤害 | `scene/components/player_health.gd` | [detail/PLAYER_SYSTEM.md](detail/PLAYER_SYSTEM.md) |
| 9 | **实体系统** | EntityBase → MonsterBase / ChimeraBase | `scene/entity_base.gd` | [detail/ENTITY_SYSTEM.md](detail/ENTITY_SYSTEM.md) |
| 10 | **怪物系统** | 各类怪物行为/属性/虚弱/眩晕 | `scene/monster_*.gd` | [detail/ENTITY_SYSTEM.md](detail/ENTITY_SYSTEM.md) |
| 11 | **奇美拉系统** | 融合产物/跟随/分解/互动 | `scene/chimera_*.gd` | [detail/ENTITY_SYSTEM.md](detail/ENTITY_SYSTEM.md) |
| 12 | **融合系统** | 规则注册/检查/执行 | `autoload/fusion_registry.gd` | [detail/FUSION_SYSTEM.md](detail/FUSION_SYSTEM.md) |
| 13 | **事件总线** | 全局信号中心 | `autoload/event_bus.gd` | [detail/EVENT_BUS.md](detail/EVENT_BUS.md) |
| 14 | **UI系统** | 锁链槽/血量/融合预测 | `ui/chain_slots_ui.gd`, `ui/hearts_ui.gd`, `ui/game_ui.gd` | [detail/UI_SYSTEM.md](detail/UI_SYSTEM.md) |
| 15 | **雷电花系统** | 能量充/放/连锁/光照 | `scene/lightning_flower.gd` | [detail/LIGHTNING_FLOWER.md](detail/LIGHTNING_FLOWER.md) |
| 16 | **天气系统** | 随机雷击/全局广播 | `systems/weather_controller.gd` | [detail/WEATHER_SYSTEM.md](detail/WEATHER_SYSTEM.md) |
| 17 | **治愈精灵** | 拾取/环绕/消耗/大爆炸 | `scene/healing_sprite.gd` | [detail/HEALING_SPRITE.md](detail/HEALING_SPRITE.md) |
| 18 | **Shader特效** | 锁链溶解/冷却填充/雷闪 | `shaders/*.gdshader` | [detail/SHADERS.md](detail/SHADERS.md) |

---

## 2. 场景树总览 — MainTest.tscn

```
MainTest (Node2D)
├── TileMap / StaticBody2D     # 地形
├── Player (CharacterBody2D)   # → player.gd
│   ├── Visual/                # Sprite/Spine + HandL/HandR Markers + center1/2/3
│   ├── Components/
│   │   ├── Movement           # PlayerMovement
│   │   ├── LocomotionFSM      # PlayerLocomotionFSM
│   │   ├── ActionFSM          # PlayerActionFSM
│   │   ├── ChainSystem        # PlayerChainSystem
│   │   ├── Health             # PlayerHealth
│   │   └── WeaponController   # WeaponController
│   ├── Animator               # PlayerAnimator → AnimDriverMock / AnimDriverSpine
│   ├── Chains/
│   │   ├── ChainLine0         # Line2D（右手链）
│   │   └── ChainLine1         # Line2D（左手链）
│   ├── CollisionShape2D       # 玩家碰撞体
│   └── HealingBurstArea       # Area2D（治愈大爆炸范围）
├── Monsters/                  # 各类怪物实例
├── LightningFlowers/          # 雷电花实例
├── WeatherController          # 天气系统
├── HealingSprites/            # 治愈精灵实例
└── UI/ (CanvasLayer)
    └── GameUI
        ├── ChainSlotsUI       # 锁链槽位 UI
        └── HeartsUI           # 血量 UI
```

---

## 3. 核心 tick 顺序（每物理帧）

```
player._physics_process(dt):
  1. Movement.tick(dt)          → 水平速度、重力、消费 jump_request
  2. move_and_slide()           → Godot 物理更新（is_on_floor 此后才准确）
  3. LocomotionFSM.tick(dt)     → 读 floor/vy/intent，评估状态转移
  4. ActionFSM.tick(dt)         → 全局 Die/Hurt 检查 + 超时保护
  5. Health.tick(dt)            → 无敌帧倒计时、击退
  6. Animator.tick(dt)          → 双轨道裁决 + 播放动画 + facing 翻转
  7. ChainSystem.tick(dt)       → Verlet 绳索更新（在 Animator 之后，读当帧骨骼）
  8. _commit_pending_chain_fire → 延迟提交链条发射（避免同帧竞态）
```

---

## 4. 武器分类架构（关键设计决策）

### 4.1 武器适配 ActionFSM 的判断标准

| 类型 | 特征 | 走 ActionFSM？ | 代表 |
|------|------|----------------|------|
| **一次性动作武器** | 短生命周期、开始/窗口/结束清晰、结束后无持续逻辑 | **是** | Sword, Knife |
| **持续系统武器** | 独立实体/跨状态长期存在/需自有 tick | **否（绕过）** | Chain |

### 4.2 Chain 的特殊性

Chain **不是** ActionFSM 管理的武器，它是一个**独立的持续系统 overlay**：
- 发射：`player.gd _unhandled_input → _pending_chain_fire_side → chain_sys.fire()`（绕过 ActionFSM）
- 动画：`PlayerAnimator.play_chain_fire()` 手动触发，`_manual_chain_anim` 标志保护不被 tick 清理
- 取消：`player.gd` 中 X 键直接调用 `chain_sys.force_dissolve_all_chains()`
- 融合：仅 Chain 武器时 Space 键触发，走 ActionFSM 的 FUSE 状态

**为什么 Chain 不能放进 ActionFSM：**
1. 链条发射后持续存在于世界（FLYING → STUCK → LINKED → DISSOLVING），不是"一次性动作"
2. 两条链独立运行，可以分别处于不同状态（一条 LINKED + 一条 IDLE）
3. 链条有自己的 tick（Verlet 物理模拟），需要跨多帧持续更新
4. 链接状态可以无限持续直到手动取消/超时/怪物挣脱
5. 链的发射/取消不应阻断 Locomotion（可以边走边发射）

### 4.3 Sword/Knife 适合 ActionFSM 的原因

1. 一次性动作：按键触发 → 播放攻击动画 → 动画结束 → 回到 None
2. 短生命周期：动画播放期间产生 hitbox，结束后 hitbox 消失
3. 清晰的开始/窗口/结束：enter → active frames → exit → resolver
4. 结束后无持续逻辑：不在世界中留下任何实体或系统

→ 详见 [detail/WEAPON_SYSTEM.md](detail/WEAPON_SYSTEM.md)

---

## 5. 锁链槽位设计

| 属性 | 值 |
|------|-----|
| 槽位数 | 2（slot 0 = 右手 R, slot 1 = 左手 L） |
| 默认活跃槽 | **1（左手）** — 这是有意设计 |
| 切换键 | Tab（手动切换 active_slot） |
| 自动切换 | 发射后自动切换到另一个空闲槽位 |
| 链状态 | IDLE → FLYING → STUCK/LINKED → DISSOLVING → IDLE |

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

**换算公式：第N层 → bitmask = 1 << (N-1)**

---

## 7. 实体继承树

```
CharacterBody2D
└── EntityBase                    # 属性/HP/泯灭融合/锁链交互/闪白/融合消失
    ├── MonsterBase               # 眩晕/虚弱/光照/雷击反应
    │   ├── MonsterWalk           # 暗属性走怪
    │   ├── MonsterWalkB          # 暗属性走怪B变体
    │   ├── MonsterFly            # 光属性飞怪（显隐机制）
    │   ├── MonsterFlyB           # 光属性飞怪B变体
    │   ├── MonsterNeutral        # 无属性中立怪
    │   ├── MonsterHostile        # 融合失败产物（敌对）
    │   └── MonsterHand           # 手怪
    └── ChimeraBase               # 跟随/漫游/分解/互动
        ├── ChimeraA              # 标准奇美拉
        ├── ChimeraTemplate       # 奇美拉模板
        └── ChimeraStoneSnake     # 石蛇奇美拉（攻击型，无法被锁链链接）
```

---

## 8. 奇美拉互动系统（重要·计划中）

**架构接口：** `ChimeraBase.on_player_interact(player: Player) -> void`

当玩家已链接一只奇美拉时，左键优先触发互动而非发射新链条。
这是一个**核心计划功能**，子类需要重写此方法实现具体互动效果。

触发路径：
```
player.gd _unhandled_input (左键)
  → 检查 active_slot 是否 LINKED 且 is_chimera
    → 是: chimera.on_player_interact(self)
    → 否: 正常发射链条
```

---

## 9. 融合结果类型

| 类型 | 枚举值 | 含义 |
|------|--------|------|
| SUCCESS | 0 | 成功融合，生成新奇美拉 |
| FAIL_HOSTILE | 1 | 失败，生成敌对体 |
| FAIL_VANISH | 2 | 泯灭（双方消失） |
| FAIL_EXPLODE | 3 | 爆炸（范围伤害） |
| HEAL_LARGE | 4 | 治愈（大量回复/奖励） |
| REJECTED | 5 | 明确拒绝（UI提示/防误触） |
| WEAKEN_BOSS | 6 | Boss弱化（预留） |

→ 详见 [detail/FUSION_SYSTEM.md](detail/FUSION_SYSTEM.md)

---

## 10. 代码规范（AI 必须遵守）

```gdscript
# ❌ 禁止
var x = cond ? A : B          # Godot 无三目运算符
var n := scene.instantiate()  # 不要用 Variant 类型推断
collision_mask = 5             # 不要手写碰撞层数字

# ✅ 正确
var x = A if cond else B
var n: Node = (scene as PackedScene).instantiate()
collision_mask = 8  # EnemyHurtbox(4) / Inspector 第4层
```

---

## 11. 自动加载（Autoload）

| Singleton名 | 文件 | 用途 |
|---|---|---|
| EventBus | `autoload/event_bus.gd` | 全局信号中心（雷击/光照/链事件/融合事件） |
| FusionRegistry | `autoload/fusion_registry.gd` | 融合规则注册/检查/执行 |

---

## 12. 文档导航

| 文档 | 路径 | 用途 |
|------|------|------|
| **本文件** | `docs/GAME_ARCHITECTURE_MASTER.md` | AI首选入口，功能总索引 |
| 项目概览 | `docs/PROJECT_OVERVIEW.md` | 项目概述+更新记录 |
| 路由器 | `docs/0_ROUTER.md` | 文档导航（旧版，仍有效） |
| 物理层表 | `docs/A_PHYSICS_LAYER_TABLE.md` | 碰撞层详细说明 |
| 玩法规则 | `docs/B_GAMEPLAY_RULES.md` | 完整玩法规则 |
| 实体目录 | `docs/C_ENTITY_DIRECTORY.md` | 所有实体的属性/场景/脚本清单 |
| 融合规则 | `docs/D_FUSION_RULES.md` | 融合公式表 |
| **详细说明** | `docs/detail/*.md` | 各模块的详细实现文档 |
| 动画规范包 | `docs/AI_Animation_Spec_Pack_/` | Spine 动画系统详细规范（12份） |
