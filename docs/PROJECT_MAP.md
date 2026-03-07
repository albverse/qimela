# PROJECT_MAP.md — 奇美拉（Qimela）入口链路与模块地图

> **维护规则**：此文件在架构发生结构性变化时更新（新模块/新实体继承链/新场景入口）。
> 推测内容用 `（推测）` 标注。验证方法写在标注后。

---

## 1. 启动入口

```
Godot 编辑器 / godot --path /path/to/qimela_git
  └── MainTest.tscn（主测试场景）
        └── Player.tscn → scene/player.gd（class_name Player）
              └── _ready()：缓存组件 + setup() 注入 + 信号连接
              └── _physics_process(dt)：8步 tick 调度
```

**Autoload（全局单例，先于任何场景加载）：**
| Singleton名 | 文件 | 职责 |
|---|---|---|
| `EventBus` | `autoload/event_bus.gd` | 全局信号中心 |
| `FusionRegistry` | `autoload/fusion_registry.gd` | 融合规则注册/检查/执行 |

---

## 2. 模块地图（18个功能模块）

| # | 模块 | 核心文件 | 详细文档 | 状态 |
|---|------|---------|---------|------|
| 1 | **玩家调度总线** | `scene/player.gd` | `docs/detail/PLAYER_SYSTEM.md` | ✅ |
| 2 | **移动系统** | `scene/components/player_movement.gd` | `docs/detail/PLAYER_SYSTEM.md` | ✅ |
| 3 | **移动状态机** | `scene/components/player_locomotion_fsm.gd` | `docs/detail/PLAYER_SYSTEM.md` | ✅ |
| 4 | **动作状态机** | `scene/components/player_action_fsm.gd` | `docs/detail/PLAYER_SYSTEM.md` | ✅ |
| 5 | **锁链系统** | `scene/components/player_chain_system.gd` | `docs/detail/CHAIN_SYSTEM.md` | ✅ |
| 6 | **武器系统** | `scene/components/weapon_controller.gd` | `docs/detail/WEAPON_SYSTEM.md` | ✅ |
| 7 | **动画系统** | `scene/components/player_animator.gd`, `anim_driver_spine.gd`, `anim_driver_mock.gd` | `docs/detail/ANIMATION_SYSTEM.md` | ✅ |
| 8 | **生命系统** | `scene/components/player_health.gd` | `docs/detail/PLAYER_SYSTEM.md` | ✅ |
| 9 | **实体基类** | `scene/entity_base.gd`, `scene/monster_base.gd`, `scene/chimera_base.gd` | `docs/detail/ENTITY_SYSTEM.md` | ✅ |
| 10 | **怪物系统** | `scene/monster_*.gd` | `docs/detail/ENTITY_SYSTEM.md` | ✅ |
| 11 | **奇美拉系统** | `scene/chimera_*.gd` | `docs/detail/ENTITY_SYSTEM.md` | ✅ |
| 12 | **融合系统** | `autoload/fusion_registry.gd` | `docs/detail/FUSION_SYSTEM.md` | ✅ |
| 13 | **事件总线** | `autoload/event_bus.gd` | `docs/detail/EVENT_BUS.md` | ✅ |
| 14 | **UI系统** | `ui/chain_slots_ui.gd`, `ui/game_ui.gd` | `docs/detail/UI_SYSTEM.md` | ✅ |
| 15 | **雷花系统** | `scene/lightning_flower.gd` | `docs/detail/LIGHTNING_FLOWER.md` | ✅ |
| 16 | **天气系统** | `systems/weather_controller.gd` | `docs/detail/WEATHER_SYSTEM.md` | ✅ |
| 17 | **治愈精灵** | `scene/healing_sprite.gd` | `docs/detail/HEALING_SPRITE.md` | ✅ |
| 18 | **Shader特效** | `shaders/*.gdshader` | `docs/detail/SHADERS.md` | ✅ |

---

## 3. 关键场景节点树

### 3.1 MainTest.tscn

```
MainTest (Node2D)
├── TileMap / StaticBody2D          # 地形（layer=World, bitmask=1）
├── Player (CharacterBody2D)        → scene/player.gd
│   ├── Visual/
│   │   ├── Sprite / SpineSkeleton  # Spine 或 Mock 视觉
│   │   ├── HandL, HandR (Marker2D) # 锁链发射锚点
│   │   ├── GhostFist               # 幽灵拳武器节点（可选）
│   │   └── center1/2/3 (Marker2D)  # 链条连接点
│   ├── Components/
│   │   ├── Movement    (PlayerMovement)
│   │   ├── LocomotionFSM (PlayerLocomotionFSM)
│   │   ├── ActionFSM   (PlayerActionFSM)
│   │   ├── ChainSystem (PlayerChainSystem)
│   │   ├── Health      (PlayerHealth)
│   │   └── WeaponController
│   ├── Animator        (PlayerAnimator → AnimDriverSpine / AnimDriverMock)
│   ├── Chains/
│   │   ├── ChainLine0  (Line2D)    # 右手链（slot 0）
│   │   └── ChainLine1  (Line2D)    # 左手链（slot 1，默认活跃）
│   ├── CollisionShape2D
│   └── HealingBurstArea (Area2D)
├── Monsters/                       # 各类怪物实例
├── LightningFlowers/               # 雷花实例
├── WeatherController               # 天气系统
├── HealingSprites/                 # 治愈精灵
└── UI/ (CanvasLayer)
    └── GameUI
        ├── ChainSlotsUI
        └── HeartsUI
```

### 3.2 Boss 场景（Beehave 驱动）

```
stone_mask_bird.tscn / StoneEyeBug.tscn
└── 根节点 (CharacterBody2D)
    ├── bt_stone_mask_bird.tscn / bt_stone_eyebug.tscn   # Beehave 行为树
    │   └── BeehaveTree → Selector/Sequence
    │       ├── conditions/*.gd    # 条件节点（7个 for StoneMaskBird）
    │       └── actions/*.gd       # 动作节点（11个 for StoneMaskBird）
    └── ... （CollisionShape / 动画 等）
```

---

## 4. 实体继承链

```
CharacterBody2D
└── EntityBase (scene/entity_base.gd)
    ├── MonsterBase (scene/monster_base.gd)
    │   ├── MonsterWalk       species_id=walk_dark      DARK
    │   ├── MonsterWalkB      species_id=walk_dark_b    DARK
    │   ├── MonsterFly        species_id=fly_light       LIGHT
    │   ├── MonsterFlyB       species_id=fly_light_b    LIGHT
    │   ├── MonsterNeutral    species_id=neutral_small  NORMAL
    │   ├── MonsterHand       species_id=hand_light      LIGHT
    │   ├── MonsterHostile    species_id=hostile_fail   NORMAL（融合失败产物）
    │   ├── StoneEyeBug       species_id=stone_eyebug   DARK（Beehave）
    │   └── Mollusc           species_id=mollusc         DARK（Beehave）
    └── ChimeraBase (scene/chimera_base.gd)
        ├── ChimeraA          species_id=chimera_a
        ├── ChimeraTemplate   species_id=（模板）
        ├── ChimeraStoneSnake species_id=chimera_stone_snake（攻击型，不可被链链接）
        └── ChimeraGhostHandL species_id=chimera_ghost_hand_l（链控飞行，鬼拳）
```

---

## 5. 关键调用链

### 5.1 每物理帧 tick（`scene/player.gd:164`）

```
_physics_process(dt)
  1. movement.tick(dt)                 # 水平速度 + 重力 + 消费 jump_request
  2. move_and_slide()                  # Godot 物理（is_on_floor 之后才准确）
  3. loco_fsm.tick(dt)                 # Idle/Walk/Run/Jump 状态机
  4. action_fsm.tick(dt)               # None/Attack/AttackCancel/Fuse/Hurt/Die
  5. health.tick(dt)                   # 无敌帧倒计时 + 击退
  6. animator.tick(dt)                 # 双轨裁决 + 骨骼/Sprite 播放 + facing 翻转
  7. chain_sys.tick(dt)                # Verlet 绳索更新（读 animator 当帧骨骼锚点）
  8. _commit_pending_chain_fire()      # 延迟提交链条发射（避免同帧竞态）
```

### 5.2 链条发射路径

```
鼠标左键 → _unhandled_input()
  → 检查 linked chimera？
      是 → chimera.on_player_interact(self)
      否 → _pending_chain_fire_side = "L"/"R"
             ↓（下帧 _commit_pending_chain_fire）
           chain_sys.fire(side, origin, target_pos)
             → animator.play_chain_fire(side)  # Track1 手动触发
             → EventBus.emit_chain_fired(id)
```

### 5.3 融合触发路径

```
Space键（仅 Chain 武器时） → _unhandled_input()
  → action_fsm.request_fuse()
      → ActionFSM 进入 FUSE 状态
          → entity_base.try_fuse(other_entity)
              → FusionRegistry.check_fusion(a, b)  → FusionResultType
              → FusionRegistry.execute_fusion(a, b, result)
                  → spawn 产物场景（奇美拉 / 敌对怪 / 治愈精灵）
                  → EventBus 广播相关事件
```

### 5.4 动画系统路径

```
animator.tick(dt)
  → _arbitrate()  # 决定 Track0/Track1 当前动画名
  → driver.play(track0_name, track1_name, blend)
      → AnimDriverSpine.play()   # Spine骨骼动画（有 Spine 资源时）
      → AnimDriverMock.play()    # AnimationPlayer fallback
```

### 5.5 EventBus 信号表（完整）

| 信号 | 参数 | 发射者 | 消费者 |
|------|------|--------|--------|
| `thunder_burst(add_seconds)` | float | WeatherController | LightningFlower |
| `healing_burst(light_energy)` | float | Player | MonsterFly（显隐） |
| `light_started(id, t, area)` | int, float, Area2D | LightningFlower | MonsterFly |
| `light_finished(id)` | int | LightningFlower | MonsterFly |
| `chain_fired(id)` | int | ChainSystem | ChainSlotsUI |
| `chain_bound(id, target, attr, icon, is_chimera, show_anim)` | … | ChainSystem | ChainSlotsUI |
| `chain_released(id, reason)` | int, StringName | ChainSystem | ChainSlotsUI |
| `chain_struggle_progress(id, t01)` | int, float | ChainSystem | ChainSlotsUI |
| `slot_switched(active_slot)` | int | Player | ChainSlotsUI |
| `fusion_rejected()` | — | Player | ChainSlotsUI |

---

## 6. 武器分类决策树

```
新武器 → 是否"一次性动作"（有清晰开始/窗口/结束且不在世界留实体）？
    是 → 走 ActionFSM（Sword, Knife 模型）
    否 → 独立 overlay 系统，绕过 ActionFSM（Chain 模型）
```

---

## 7. 文件清单摘要（供 glob 快速定位）

```
scene/player.gd                              # 玩家总线
scene/components/player_*.gd                # 玩家所有组件
scene/components/anim_driver_*.gd           # 动画驱动器
scene/entity_base.gd                        # 实体基类
scene/monster_base.gd                       # 怪物基类
scene/chimera_base.gd                       # 奇美拉基类
scene/monster_*.gd                          # 各类怪物
scene/chimera_*.gd                          # 各类奇美拉
scene/enemies/stone_mask_bird/              # Boss（Beehave行为树）
scene/enemies/stone_eyebug/                 # 石眼虫家族（Beehave行为树）
scene/enemies/chimera_ghost_hand_l/         # 幽灵手奇美拉（Beehave）
autoload/event_bus.gd                       # 事件总线
autoload/fusion_registry.gd                 # 融合注册表
anim/weapon_anim_profiles.gd               # 武器动画配置
combat/hit_data.gd                          # 命中数据结构
systems/weather_controller.gd               # 天气控制
ui/chain_slots_ui.gd                        # 锁链UI
shaders/*.gdshader                          # 所有Shader
spine_assets/                               # Spine骨骼资源
docs/AI_Animation_Spec_Pack_/               # 动画规范包（Spine/Action合规）
```
