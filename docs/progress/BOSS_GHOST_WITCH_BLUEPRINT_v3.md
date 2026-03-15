# 《幽灵魔女（BossGhostWitch）工程蓝图 v3.0》— 全三阶段正式版

> **目标**：AI 可直接执行的工程规范（Godot 4.5 + GDScript + Beehave 2.9.2 + Spine2D）。
> **范围**：Phase 1（石像形态）+ Phase 2（祈祷形态）+ Phase 3（无头骑士形态），全部内容。
> **关键参考**：`BEEHAVE_REFERENCE.md`（行为树）、`SPINE_GODOT_LATEST_INTEGRATED_STANDARD.md`（动画驱动）。

---

## 0. 名词归一

| 需求原词 | 工程标准名 | 备注 |
|---|---|---|
| 幽灵魔女 / Boss本体 | `BossGhostWitch`（class_name） | 场景：`scene/enemies/boss_ghost_witch/BossGhostWitch.tscn` |
| 婴儿石像 / 光环核心 | `BabyStatue`（子节点名） | 魔女场景内子节点，不是独立实例 |
| 幽灵拔河 | `GhostTug`（实例） | 绑定玩家的拉拽实例 |
| 自爆幽灵 | `GhostBomb`（实例） | 被动技能释放 |
| 亡灵气流幽灵 | `GhostWraith`（实例） | type 参数区分 1/2/3 三种形态 |
| 精英亡灵 | `GhostElite`（实例） | HP=1，被 ghostfist 打中扣 Boss 血 |
| ghostfist / 鬼拳 | `ghost_fist`（weapon_id） | 唯一能对 realhurtbox 造成伤害的武器 |
| realhurtbox | `RealHurtbox`（Area2D 节点名） | 复用 EnemyHurtbox(4) 层的变体 |
| bodybox | `BodyBox`（Area2D 节点名） | 只检测武器抵消，不触发伤害 |
| chain | 锁链武器 | 本 Boss 战中无法对任何 box 造成伤害 |
| 镰刀检测区 | `ScytheDetectArea`（Area2D） | Phase 1 start_attack 与 Phase 2 镰刀斩共用 |
| mark2D-hug | `Mark2D_Hug`（Marker2D） | 婴儿石像在 Phase 1 的绑定点（怀抱位置）|
| mark2D-hale | `Mark2D_Hale`（Marker2D） | 光环在 Phase 2 的绑定点（头顶位置）|
| 无头骑士 | Phase 3 形态 | Boss 同一实例，动画前缀 `phase3/` |
| 镰刀实例 | `WitchScythe`（实例） | Phase 3 扔出的镰刀 |
| 地狱之手 | `HellHand`（实例） | 禁锢陷阱 |
| 召唤幽灵（P3） | `GhostSummon`（实例） | 地面圆圈飞出的幽灵 |

---

## 1. 与当前项目硬规则的对齐约束

1. **实体类型**：`entity_type = EntityType.MONSTER`，`size_tier = SizeTier.LARGE`。
2. **不参与融合系统**：`attribute_type = AttributeType.NORMAL`，融合相关值全部保持默认。同 species_id 无法融合规则自动满足。
3. **锁链完全无效**：`on_chain_hit` 始终返回 0，chain 碰到 bodybox 直接溶解消失，无任何伤害。
4. **唯一伤害路径**：只有 `ghost_fist`（weapon_id = `&"ghost_fist"`）命中 `RealHurtbox` 才造成真实伤害。
5. **无 weak / stun / vanish 状态**：此 Boss 不使用 MonsterBase 的 weak_hp 阈值、stun 机制、vanish_fusion 流程。全部 override 跳过。
6. **HP 模型**：总 HP = 30，每阶段耐受 10 点。当累计伤害达到 10 / 20 时锁定 hp_locked 进入变身，变身期间无敌。
7. **Beehave 行为树驱动**：冷却全部在 ActionLeaf 内自管理（不用 CooldownDecorator），ConditionLeaf 自给自足感知。
8. **攻击判定由 Spine 动画事件驱动**：禁止纯定时器猜命中窗口。
9. **可调参数全部 `@export`**。
10. **SpineSprite + AnimDriverSpine**：动画播放接口与修女蛇一致（`anim_play`、`anim_is_finished` 等）。

---

## 2. 实体注册（C_ENTITY_DIRECTORY.md 追加）

| species_id | 场景文件 | 脚本文件 | attribute | size | 备注 |
|---|---|---|---|---|---|
| `boss_ghost_witch` | `BossGhostWitch.tscn` | `boss_ghost_witch.gd` | NORMAL | LARGE | Boss 主实体 |

**子实例场景（从 Boss 场景中 instantiate）：**

| species_id | 场景文件 | 说明 | 可被 ghostfist 摧毁 | 可被 chain 伤害 |
|---|---|---|---|---|
| `ghost_tug` | `GhostTug.tscn` | 幽灵拔河 | 是（打断技能） | 否 |
| `ghost_bomb` | `GhostBomb.tscn` | 自爆幽灵 | 是 | 否 |
| `ghost_wraith` | `GhostWraith.tscn` | 亡灵气流（type 1/2/3） | 是 | 否 |
| `ghost_elite` | `GhostElite.tscn` | 精英亡灵 | 是（扣 Boss HP-1） | 否 |
| `witch_scythe` | `WitchScythe.tscn` | Phase 3 镰刀实例 | 否（回航用） | 否 |
| `hell_hand` | `HellHand.tscn` | Phase 3 禁锢陷阱 | 是（ghostfist 解禁锢） | 否 |
| `ghost_summon` | `GhostSummon.tscn` | Phase 3 召唤幽灵 | 否（自然消失） | 否 |

> 以上子实例均不参与融合，attribute 和 size 保持默认即可。

---

## 3. 物理层/碰撞配置

### 3.1 现有层复用（不新建物理层）

| 层号 | 层名 | bitmask |
|---|---|---|
| 1 | World | 1 |
| 2 | PlayerBody | 2 |
| 3 | EnemyBody | 4 |
| 4 | EnemyHurtbox | 8 |
| 5 | ObjectSense | 16 |
| 6 | hazards | 32 |
| 7 | ChainInteract | 64 |

### 3.2 Boss 各 Box 碰撞配置

| 节点名 | collision_layer | collision_mask | 说明 |
|---|---|---|---|
| `BodyBox` | `64` (ChainInteract(7)) | `2` (PlayerBody(2)) | 被 chain 检测到但无伤害；能感知玩家但不堵路 |
| `RealHurtbox` | `8` (EnemyHurtbox(4)) | `0` | 只被 ghostfist 的 hitbox 主动检测。默认 disabled |
| `ScytheDetectArea` | `0` | `2` (PlayerBody(2)) | 检测玩家是否在近身范围。monitoring=true |
| Boss CharacterBody2D | `4` (EnemyBody(3)) | `1` (World(1)) | 与地形碰撞 |

### 3.3 Platform 穿透方案

- Platform 使用 Godot 内置 `one_way_collision = true`，仍放 World(1) 层。
- Boss 的 `CharacterBody2D` 设置 `floor_snap_length = 0`，下落时不处理单向碰撞逻辑，可穿过 platform 只与 ground 碰撞。
- 玩家正常可以站在 platform 上。

### 3.4 Boss 测试专用场景

需新建 `scene/levels/BossTestArena.tscn`：
- **Ground**：底部地面，`StaticBody2D` + `CollisionShape2D`，World(1) 层。
- **Platform × 2~3**：空中浮板，`one_way_collision = true`。玩家站上后 2 秒消失，3 秒后恢复（用 `Timer` + `set_deferred("disabled", true/false)` 控制碰撞体）。
- **PlayerSpawn**：`Marker2D`，玩家出生点。
- **BossSpawn**：`Marker2D`，Boss 出生点。

---

## 4. HP 系统设计

### 4.1 整体模型

```
总 HP = 30
Phase 1: HP 30→20（承受 10 点伤害触发变身）
Phase 2: HP 20→10（承受 10 点伤害触发变身）
Phase 3: HP 10→0 （承受 10 点伤害死亡）
```

### 4.2 boss_ghost_witch.gd 中的 HP 管理

```gdscript
# _ready() 中
max_hp = 30
hp = 30
weak_hp = 0          # 不使用 weak 机制
vanish_fusion_required = 0  # 不可泯灭

# 阶段阈值
const PHASE2_HP_THRESHOLD: int = 20  # hp <= 20 → 进入 Phase 2
const PHASE3_HP_THRESHOLD: int = 10  # hp <= 10 → 进入 Phase 3

# 当前阶段
enum Phase { PHASE1 = 1, PHASE2 = 2, PHASE3 = 3 }
var current_phase: int = Phase.PHASE1
```

### 4.3 伤害传导路径

1. 玩家的 ghostfist hitbox 进入 `RealHurtbox` 区域 → 触发 `_on_real_hurtbox_hit()`
2. 若 `RealHurtbox` 在婴儿石像上 → 婴儿石像调用 Boss 本体的 `apply_real_damage(1)`
3. `apply_real_damage()` — 完整实现见 §12（含 Phase 3 镰刀回航逻辑）：
   ```gdscript
   func apply_real_damage(amount: int) -> void:
       if hp_locked:
           _flash_once()
           return
       hp = max(hp - amount, 0)
       _flash_once()

       # Phase 3 扔镰刀期间被打 → 触发镰刀回航
       if current_phase == Phase.PHASE3 and not _scythe_in_hand:
           _scythe_recall_requested = true

       # 阶段切换检查
       if current_phase == Phase.PHASE1 and hp <= phase2_hp_threshold:
           _begin_phase_transition(Phase.PHASE2)
       elif current_phase == Phase.PHASE2 and hp <= phase3_hp_threshold:
           _begin_phase_transition(Phase.PHASE3)
       elif hp <= 0:
           _begin_death()
   ```
4. **变身期间**：`hp_locked = true`，任何伤害只闪白不扣血。变身动画播完后 `hp_locked = false`。

### 4.4 override 基类受击

```gdscript
func apply_hit(hit: HitData) -> bool:
    # 此 Boss 的 apply_hit 只处理来自 ghostfist 的伤害
    # chain 和其他武器一律无效
    if hit == null:
        return false
    if hit.weapon_id != &"ghost_fist":
        _flash_once()  # 视觉反馈但无伤害
        return false
    apply_real_damage(hit.damage)
    return true

func on_chain_hit(_player: Node, _slot: int) -> int:
    # 锁链完全无效，永远返回 0（不可链接）
    _flash_once()
    return 0
```

---

## 5. 场景节点结构

### 5.1 BossGhostWitch.tscn 主场景树

```
BossGhostWitch (CharacterBody2D)  # boss_ghost_witch.gd
├── SpineSprite                    # 魔女石像的 Spine 动画
├── BodyBox (Area2D)               # 武器抵消用（ChainInteract 层）
│   └── CollisionShape2D
├── RealHurtbox (Area2D)           # 真实受击区（Phase 2 后绑定 hale 骨骼）
│   └── CollisionShape2D           # 默认 disabled
├── ScytheDetectArea (Area2D)      # 镰刀斩 / start_attack 检测区
│   └── CollisionShape2D
├── GroundHitbox (Area2D)          # Phase 2 飞天砸落的落地伤害区
│   └── CollisionShape2D           # 默认 disabled
├── Mark2D_Hug (Marker2D)         # 婴儿石像 Phase 1 绑定点（怀抱）
├── Mark2D_Hale (Marker2D)        # 光环 Phase 2 绑定点（头顶）
├── BabyStatue (Node2D)           # 婴儿石像子节点
│   ├── SpineSprite               # 婴儿石像的 Spine 动画
│   ├── BabyBodyBox (Area2D)      # 婴儿的 bodybox（同 BodyBox 碰撞配置）
│   │   └── CollisionShape2D
│   ├── BabyRealHurtbox (Area2D)  # 婴儿的 realhurtbox（挂载在 core 骨骼）
│   │   └── CollisionShape2D      # 默认 disabled
│   ├── BabyAttackArea (Area2D)   # 婴儿冲刺伤害区（冲刺期间碰到玩家即伤害）
│   │   └── CollisionShape2D      # 默认 disabled
│   ├── BabyExplosionArea (Area2D) # 婴儿爆炸范围伤害区
│   │   └── CollisionShape2D       # 默认 disabled
│   └── BabyDetectArea (Area2D)   # 婴儿检测玩家是否在范围内（决定是否冲刺）
│       └── CollisionShape2D       # monitoring=true
├── DetectArea500 (Area2D)         # 500px 范围检测
│   └── CollisionShape2D (CircleShape2D, radius=500)
├── DetectArea300 (Area2D)         # 300px 范围检测
│   └── CollisionShape2D (CircleShape2D, radius=300)
├── DetectArea100 (Area2D)         # 100px 范围检测
│   └── CollisionShape2D (CircleShape2D, radius=100)
├── AnimDriverSpine                # 动画驱动（与修女蛇同款）
├── BeehaveTree (Node)             # 行为树根节点
│   └── ... (见第 7 节)
└── Blackboard (Node)              # 行为树黑板
```

### 5.2 婴儿石像（BabyStatue）的设计要点

**关键决策：婴儿石像是 Boss 场景的子节点，不是独立实例。**

- **Phase 1**：
  - 默认 `global_position = Mark2D_Hug.global_position`（怀抱中）
  - 投掷时：脱离 Mark2D_Hug 约束，自由飞行
  - 返航时：飞回 Mark2D_Hug 位置，重新绑定
  - `BabyRealHurtbox` 默认 disabled，爆炸后临时开启
  
- **Phase 1→2 过渡**：
  - 婴儿播放 `baby/phase1_to_phase2` → 变为光环形态
  - `BabyBodyBox` 永久 disabled
  - `BabyRealHurtbox` 永久 enabled
  - 绑定点从 `Mark2D_Hug` 切到 `Mark2D_Hale`
  - 光环到达 hale 后，魔女播放 `phase1/phase1_to_phase2`
  - 魔女动画切到 `phase2/idle` 的同时：`BabyStatue.visible = false`，`BabyStatue` 不再 tick
  - `RealHurtbox`（Boss 本体的）换绑到魔女 SpineSprite 的 `hale` 骨骼，永久 enabled

### 5.3 婴儿石像的 RealHurtbox 到 Boss HP 的传导

```gdscript
# baby_statue 不需要独立脚本，逻辑写在 boss_ghost_witch.gd 中

# BabyRealHurtbox 的 area_entered 信号连接：
func _on_baby_real_hurtbox_area_entered(area: Area2D) -> void:
    # 只接受 ghostfist 的 hitbox
    if not _is_ghostfist_hitbox(area):
        return
    if not _baby_realhurtbox_active:
        return
    apply_real_damage(1)

func _is_ghostfist_hitbox(area: Area2D) -> bool:
    # 检查 area 是否属于 ghostfist 的攻击判定
    var parent = area.get_parent()
    if parent != null and parent is GhostFist:
        return true
    # 或通过 group 判断
    return area.is_in_group("ghost_fist_hitbox")
```

### 5.4 RealHurtbox 骨骼跟随（运行时每帧同步）

```gdscript
# 在 _physics_process 中
func _sync_hurtboxes() -> void:
    match current_phase:
        Phase.PHASE1:
            # 婴儿的 BabyRealHurtbox 跟随婴儿 SpineSprite 的 core 骨骼
            if _baby_realhurtbox_active:
                var core_pos: Vector2 = _baby_anim_driver.get_bone_world_position("core")
                if core_pos != Vector2.ZERO:
                    _baby_real_hurtbox.global_position = core_pos
        Phase.PHASE2:
            # Boss 本体的 RealHurtbox 跟随魔女 SpineSprite 的 hale 骨骼
            var hale_pos: Vector2 = _anim_driver.get_bone_world_position("hale")
            if hale_pos != Vector2.ZERO:
                _real_hurtbox.global_position = hale_pos
        Phase.PHASE3:
            # Phase 3 延续 hale 骨骼跟随 + KickHitbox 跟随 leg 骨骼
            _sync_phase3_hitboxes()
```

---

## 6. 主脚本结构（boss_ghost_witch.gd）

```gdscript
extends MonsterBase
class_name BossGhostWitch

# ═══════════════════════════════════════
# 阶段枚举
# ═══════════════════════════════════════
enum Phase { PHASE1 = 1, PHASE2 = 2, PHASE3 = 3 }
enum BabyState { IN_HUG, THROWN, EXPLODED, REPAIRING, DASHING, POST_DASH_WAIT, WINDING_UP, RETURNING, HALO }

# ═══════════════════════════════════════
# 导出参数（Inspector 可调）
# ═══════════════════════════════════════
# -- HP --
@export var phase2_hp_threshold: int = 20
@export var phase3_hp_threshold: int = 10

# -- Phase 1 参数 --
@export var detect_range_px: float = 500.0         # 投掷婴儿的检测范围
@export var slow_move_speed: float = 30.0           # 石像缓慢移动速度
@export var baby_throw_speed: float = 600.0         # 婴儿投掷飞行速度
@export var baby_explosion_radius: float = 80.0     # 婴儿爆炸范围
@export var baby_repair_duration: float = 2.0       # 婴儿修复动画时长
@export var baby_dash_speed: float = 400.0          # 攻击流1冲刺速度
@export var baby_post_dash_wait: float = 0.7        # 冲刺到达后等待时间（秒）
@export var baby_return_speed: float = 500.0        # 收招后飞回母体速度
@export var start_attack_loop_duration: float = 4.0 # 开场 loop 停留秒数

# -- Phase 2 参数 --
@export var scythe_slash_cooldown: float = 1.0
@export var tombstone_drop_cooldown: float = 3.0
@export var undead_wind_cooldown: float = 15.0
@export var ghost_tug_cooldown: float = 5.0
@export var ghost_tug_pull_speed: float = 400.0     # 拔河拉拽速度(px/s)
@export var tombstone_offset_y: float = 400.0       # 墓碑出现在玩家头上的 Y 偏移
@export var tombstone_offset_x_range: float = 70.0  # 墓碑 X 偏移随机 ±
@export var tombstone_hover_duration: float = 0.5    # 空中悬停时间（秒）
@export var tombstone_fall_duration: float = 0.5     # 下落时间
@export var tombstone_stagger_duration: float = 1.0  # 落地僵直
@export var undead_wind_spawn_duration: float = 7.0  # 亡灵气流生成总时长
@export var undead_wind_total_count: int = 10        # 普通亡灵总数
@export var ghost_bomb_interval: float = 5.0         # 自爆幽灵生成间隔
@export var ghost_bomb_max_count: int = 3            # 场上最多自爆幽灵
@export var ghost_bomb_light_energy: float = 5.0     # 自爆光照能量

# ═══════════════════════════════════════
# 运行时状态
# ═══════════════════════════════════════
var current_phase: int = Phase.PHASE1
var baby_state: int = BabyState.IN_HUG
var _phase_transitioning: bool = false  # 变身动画中
var _battle_started: bool = false        # 是否已完成开场动画
var _baby_realhurtbox_active: bool = false
var _baby_dash_go_triggered: bool = false  # baby/dash 的 Spine 事件 "dash_go" 是否已触发

# 冷却管理（blackboard 自管理模式）
# 见第 7 节 ActionLeaf 中的实现

# ═══════════════════════════════════════
# 子节点引用
# ═══════════════════════════════════════
@onready var _spine_sprite: Node = $SpineSprite
@onready var _baby_statue: Node2D = $BabyStatue
@onready var _baby_spine: Node = $BabyStatue/SpineSprite
@onready var _body_box: Area2D = $BodyBox
@onready var _real_hurtbox: Area2D = $RealHurtbox
@onready var _baby_real_hurtbox: Area2D = $BabyStatue/BabyRealHurtbox
@onready var _baby_body_box: Area2D = $BabyStatue/BabyBodyBox
@onready var _baby_attack_area: Area2D = $BabyStatue/BabyAttackArea
@onready var _baby_explosion_area: Area2D = $BabyStatue/BabyExplosionArea
@onready var _baby_detect_area: Area2D = $BabyStatue/BabyDetectArea
@onready var _scythe_detect_area: Area2D = $ScytheDetectArea
@onready var _ground_hitbox: Area2D = $GroundHitbox
@onready var _mark_hug: Marker2D = $Mark2D_Hug
@onready var _mark_hale: Marker2D = $Mark2D_Hale

# 预加载子实例场景
var _ghost_tug_scene: PackedScene = preload("res://scene/enemies/boss_ghost_witch/GhostTug.tscn")
var _ghost_bomb_scene: PackedScene = preload("res://scene/enemies/boss_ghost_witch/GhostBomb.tscn")
var _ghost_wraith_scene: PackedScene = preload("res://scene/enemies/boss_ghost_witch/GhostWraith.tscn")
var _ghost_elite_scene: PackedScene = preload("res://scene/enemies/boss_ghost_witch/GhostElite.tscn")

# 动画驱动
var _anim_driver: AnimDriverSpine = null
var _baby_anim_driver: AnimDriverSpine = null
# ... mock 驱动省略，结构同修女蛇
```

### 6.1 _ready() 初始化

```gdscript
func _ready() -> void:
    species_id = &"boss_ghost_witch"
    entity_type = EntityType.MONSTER
    attribute_type = AttributeType.NORMAL
    size_tier = SizeTier.LARGE
    max_hp = 30
    hp = 30
    weak_hp = 0
    vanish_fusion_required = 0

    super._ready()
    add_to_group("monster")
    add_to_group("boss")

    # 初始化两个 AnimDriverSpine（魔女 + 婴儿）
    _setup_anim_drivers()

    # 初始状态：Phase 1，婴儿在怀中
    _enter_phase1()

    # 关闭所有攻击 hitbox
    _disable_all_hitboxes()
```

### 6.2 _physics_process()

```gdscript
func _physics_process(dt: float) -> void:
    # 光照系统（保持基类兼容）
    if light_counter > 0.0:
        light_counter -= dt
        light_counter = max(light_counter, 0.0)
    _thunder_processed_this_frame = false

    # 骨骼跟随
    _sync_hurtboxes()

    # 婴儿石像位置管理
    if current_phase == Phase.PHASE1 and baby_state == BabyState.IN_HUG:
        _baby_statue.global_position = _mark_hug.global_position

    # 重力（仅 Phase 2 飞天砸落后需要）
    if not is_on_floor():
        velocity.y += dt * 1200.0
    else:
        velocity.y = max(velocity.y, 0.0)
    move_and_slide()

    # 不调用 super._physics_process()
    # BeehaveTree 由其自身 _physics_process 驱动
```

---

## 7. 行为树结构

### 7.1 Phase 1 行为树

```
BeehaveTree
└── SelectorReactiveComposite [RootSelector]
    │
    ├── SequenceReactiveComposite [PhaseTransitionSeq]
    │   ├── CondPhaseTransitioning        ← hp_locked / 变身中 → SUCCESS
    │   └── ActWaitTransition             ← RUNNING 直到变身完毕
    │
    ├── SequenceReactiveComposite [Phase1Seq]
    │   ├── CondIsPhase (phase=1)
    │   └── SelectorReactiveComposite [P1Selector]
    │       │
    │       ├── SequenceReactiveComposite [P1StartBattleSeq]
    │       │   ├── CondBattleNotStarted
    │       │   └── ActStartBattle         ← 开场动画流程
    │       │
    │       ├── SequenceReactiveComposite [P1ThrowBabySeq]
    │       │   ├── CondBabyInHug
    │       │   ├── CondPlayerInRange (range=500)
    │       │   └── ActThrowBaby           ← 投掷婴儿石像
    │       │
    │       ├── SequenceReactiveComposite [P1BabyAttackFlowSeq]
    │       │   ├── CondBabyNotInHug
    │       │   └── ActBabyAttackFlow      ← 婴儿爆炸→修复→检测→冲刺→等待→冲回→收招→返航
    │       │
    │       └── ActSlowMoveToPlayer        ← 兜底：玩家不在攻击范围内 → 缓慢向玩家移动
    │
    ├── SequenceReactiveComposite [Phase2Seq]
    │   ├── CondIsPhase (phase=2)
    │   └── SelectorReactiveComposite [P2Selector]
    │       │  (见 7.2)
    │       └── ...
    │
    └── SequenceReactiveComposite [Phase3Seq]
        ├── CondIsPhase (phase=3)
        └── SelectorReactiveComposite [P3Selector]
            │  (见 14.2)
```

### 7.2 Phase 2 行为树

```
SelectorReactiveComposite [P2Selector]
│
├── SequenceReactiveComposite [P2ScytheSlashSeq]     ← 优先级 1（最高）
│   ├── CondPlayerInRange (range=100)
│   ├── CondCooldownReady (key="cd_scythe", cooldown=scythe_slash_cooldown)
│   └── ActScytheSlash
│
├── SequenceReactiveComposite [P2TombstoneSeq]       ← 优先级 2
│   ├── CondPlayerInRange (range=500)
│   ├── CondCooldownReady (key="cd_tombstone", cooldown=tombstone_drop_cooldown)
│   └── ActTombstoneDrop
│
├── SequenceReactiveComposite [P2UndeadWindSeq]      ← 优先级 3
│   ├── CondPlayerInRange (range=300)
│   ├── InverterDecorator
│   │   └── CondPlayerInRange (range=100)             ← NOT: 100px以内不触发
│   ├── CondCooldownReady (key="cd_wind", cooldown=undead_wind_cooldown)
│   └── ActUndeadWind
│
├── SequenceReactiveComposite [P2GhostTugSeq]        ← 优先级 4
│   ├── InverterDecorator
│   │   └── CondPlayerInRange (range=500)             ← NOT: 500px以内不触发
│   ├── CondCooldownReady (key="cd_tug", cooldown=ghost_tug_cooldown)
│   └── ActGhostTug
│
├── SequenceReactiveComposite [P2PassiveBombSeq]     ← 被动技能（空闲时）
│   ├── CondAllSkillsOnCooldown
│   ├── CondGhostBombCanSpawn (max_count=3)
│   ├── CondCooldownReady (key="cd_bomb", cooldown=ghost_bomb_interval)
│   └── ActSpawnGhostBomb
│
└── ActMoveTowardPlayer                               ← 兜底：玩家不在攻击范围内 / 技能冷却中 → 向玩家移动
```

### 7.3 攻击优先级总结（Phase 2 距离范围解析）

```
玩家距离 ≤ 100px   → 镰刀斩（cd=1s）; 冷却中 → 等待
100px < 距离 ≤ 300px → 先检查亡灵气流（cd=15s）; 冷却中 → 飞天砸落
300px < 距离 ≤ 500px → 飞天砸落（cd=3s）; 冷却中 → 缓慢向玩家移动
距离 > 500px       → 幽灵拔河（cd=5s）; 冷却中 → 缓慢向玩家移动
所有技能冷却中     → 释放自爆幽灵 / 缓慢向玩家移动
任何时候玩家超出全部攻击检测范围 → 缓慢向玩家移动（SelectorReactive 自然落到末位兜底分支）
```

---

## 8. 自定义 Condition/Action 叶节点详细设计

### 8.1 通用 ConditionLeaf

#### CondIsPhase

```gdscript
## 检查 Boss 当前是否处于指定阶段
class_name CondIsPhase extends ConditionLeaf

@export var phase: int = 1

func tick(actor: Node, _blackboard: Blackboard) -> int:
    var boss: BossGhostWitch = actor as BossGhostWitch
    if boss == null: return FAILURE
    return SUCCESS if boss.current_phase == phase else FAILURE
```

#### CondPhaseTransitioning

```gdscript
## 检查 Boss 是否正在变身
class_name CondPhaseTransitioning extends ConditionLeaf

func tick(actor: Node, _blackboard: Blackboard) -> int:
    var boss: BossGhostWitch = actor as BossGhostWitch
    if boss == null: return FAILURE
    return SUCCESS if boss._phase_transitioning else FAILURE
```

#### CondPlayerInRange

```gdscript
## 自给自足感知：检测玩家是否在指定范围内
class_name CondPlayerInRange extends ConditionLeaf

@export var range_px: float = 500.0

func tick(actor: Node, blackboard: Blackboard) -> int:
    var boss: BossGhostWitch = actor as BossGhostWitch
    if boss == null: return FAILURE
    var player: Node2D = boss.get_priority_attack_target()
    if player == null: return FAILURE
    # 使用水平距离（2D 横向游戏）
    var h_dist: float = abs(player.global_position.x - actor.global_position.x)
    if h_dist <= range_px:
        var actor_id := str(actor.get_instance_id())
        blackboard.set_value("player", player, actor_id)
        return SUCCESS
    return FAILURE
```

#### CondCooldownReady（自管理冷却模式）

```gdscript
## 检查指定技能是否冷却完毕（blackboard 自管理，不受 interrupt 影响）
class_name CondCooldownReady extends ConditionLeaf

@export var cooldown_key: String = "cd_skill"
@export var cooldown_sec: float = 3.0

func tick(actor: Node, blackboard: Blackboard) -> int:
    var actor_id := str(actor.get_instance_id())
    var end_time: float = blackboard.get_value(cooldown_key, 0.0, actor_id)
    if Time.get_ticks_msec() < end_time:
        return FAILURE
    return SUCCESS
```

#### CondBabyInHug / CondBabyNotInHug

```gdscript
class_name CondBabyInHug extends ConditionLeaf
func tick(actor: Node, _bb: Blackboard) -> int:
    var boss := actor as BossGhostWitch
    return SUCCESS if boss != null and boss.baby_state == BossGhostWitch.BabyState.IN_HUG else FAILURE

class_name CondBabyNotInHug extends ConditionLeaf
func tick(actor: Node, _bb: Blackboard) -> int:
    var boss := actor as BossGhostWitch
    return SUCCESS if boss != null and boss.baby_state != BossGhostWitch.BabyState.IN_HUG else FAILURE
```

#### CondBattleNotStarted

```gdscript
class_name CondBattleNotStarted extends ConditionLeaf
func tick(actor: Node, _bb: Blackboard) -> int:
    var boss := actor as BossGhostWitch
    return SUCCESS if boss != null and not boss._battle_started else FAILURE
```

#### CondAllSkillsOnCooldown

```gdscript
## Phase 2 用：检查所有主动技能是否都在冷却中
class_name CondAllSkillsOnCooldown extends ConditionLeaf

func tick(actor: Node, blackboard: Blackboard) -> int:
    var actor_id := str(actor.get_instance_id())
    var now_ms: float = Time.get_ticks_msec()
    # 只要任意一个技能可用，就返回 FAILURE（不是"全部冷却中"）
    for key in ["cd_scythe", "cd_tombstone", "cd_wind", "cd_tug"]:
        var end_time: float = blackboard.get_value(key, 0.0, actor_id)
        if now_ms >= end_time:
            return FAILURE  # 有技能可用
    return SUCCESS  # 全部冷却中
```

#### CondGhostBombCanSpawn

```gdscript
class_name CondGhostBombCanSpawn extends ConditionLeaf
@export var max_count: int = 3

func tick(actor: Node, _bb: Blackboard) -> int:
    var bombs: Array[Node] = actor.get_tree().get_nodes_in_group("ghost_bomb")
    return SUCCESS if bombs.size() < max_count else FAILURE
```

---

### 8.2 Phase 1 ActionLeaf

#### ActStartBattle（开场动画流）

```gdscript
## 首次检测到玩家 → start_attack → start_attack_loop(4s) → start_attack_exter → 战斗开始
class_name ActStartBattle extends ActionLeaf

enum Step { PLAY_START, WAIT_START, PLAY_LOOP, WAIT_LOOP, PLAY_EXTER, WAIT_EXTER, DONE }
var _step: int = Step.PLAY_START
var _loop_end_time: float = 0.0

func before_run(actor: Node, _bb: Blackboard) -> void:
    _step = Step.PLAY_START

func tick(actor: Node, blackboard: Blackboard) -> int:
    var boss := actor as BossGhostWitch
    if boss == null: return FAILURE

    match _step:
        Step.PLAY_START:
            boss.anim_play(&"phase1/start_attack", false)
            _step = Step.WAIT_START
            return RUNNING
        Step.WAIT_START:
            if boss.anim_is_finished(&"phase1/start_attack"):
                # 检测玩家是否在镰刀检测区
                if _player_in_scythe_area(boss):
                    _damage_player(boss, 1)
                _step = Step.PLAY_LOOP
            return RUNNING
        Step.PLAY_LOOP:
            boss.anim_play(&"phase1/start_attack_loop", true)
            _loop_end_time = Time.get_ticks_msec() + boss.start_attack_loop_duration * 1000.0
            _step = Step.WAIT_LOOP
            return RUNNING
        Step.WAIT_LOOP:
            if Time.get_ticks_msec() >= _loop_end_time:
                _step = Step.PLAY_EXTER
            return RUNNING
        Step.PLAY_EXTER:
            boss.anim_play(&"phase1/start_attack_exter", false)
            _step = Step.WAIT_EXTER
            return RUNNING
        Step.WAIT_EXTER:
            if boss.anim_is_finished(&"phase1/start_attack_exter"):
                boss._battle_started = true
                return SUCCESS
            return RUNNING
    return FAILURE

func _player_in_scythe_area(boss: BossGhostWitch) -> bool:
    # 通过 ScytheDetectArea.get_overlapping_bodies() 检测玩家
    for body in boss._scythe_detect_area.get_overlapping_bodies():
        if body.is_in_group("player"):
            return true
    return false

func _damage_player(boss: BossGhostWitch, amount: int) -> void:
    for body in boss._scythe_detect_area.get_overlapping_bodies():
        if body.is_in_group("player") and body.has_method("apply_damage"):
            body.call("apply_damage", amount, boss.global_position)

func interrupt(actor: Node, blackboard: Blackboard) -> void:
    _step = Step.PLAY_START
    super(actor, blackboard)
```

#### ActThrowBaby（投掷婴儿石像）

```gdscript
## 播放抛婴儿动画 → 婴儿从 mark2D_hug 发射飞向玩家 → 进入 THROWN 状态
class_name ActThrowBaby extends ActionLeaf

enum Step { ANIM_THROW, WAIT_ANIM, BABY_FLYING, DONE }
var _step: int = Step.ANIM_THROW
var _target_pos: Vector2 = Vector2.ZERO

func before_run(actor: Node, _bb: Blackboard) -> void:
    _step = Step.ANIM_THROW

func tick(actor: Node, blackboard: Blackboard) -> int:
    var boss := actor as BossGhostWitch
    if boss == null: return FAILURE
    var actor_id := str(actor.get_instance_id())
    var player: Node2D = blackboard.get_value("player", null, actor_id)

    match _step:
        Step.ANIM_THROW:
            if player == null: return FAILURE
            _target_pos = player.global_position
            boss.anim_play(&"phase1/throw", false)
            _step = Step.WAIT_ANIM
            return RUNNING
        Step.WAIT_ANIM:
            # 等待 Spine 事件 "baby_release" 触发
            # 事件回调中会设置 boss.baby_state = BabyState.THROWN
            # 并让婴儿 SpineSprite visible，开始飞行
            if boss.baby_state == BossGhostWitch.BabyState.THROWN:
                _step = Step.BABY_FLYING
            return RUNNING
        Step.BABY_FLYING:
            # 婴儿飞行中播放旋转动画
            boss.baby_anim_play(&"baby/spin", true)
            # 飞行移动逻辑在 boss._tick_baby_flight() 中处理
            # 婴儿撞到地面 → 自动进入 EXPLODED
            if boss.baby_state != BossGhostWitch.BabyState.THROWN:
                return SUCCESS
            return RUNNING
    return FAILURE

func interrupt(actor: Node, blackboard: Blackboard) -> void:
    _step = Step.ANIM_THROW
    super(actor, blackboard)
```

#### ActBabyAttackFlow（婴儿攻击流1：爆炸→修复→检测→冲刺→等待→冲回→收招→返航）

```gdscript
## 婴儿石像的完整攻击循环（多帧状态机）
class_name ActBabyAttackFlow extends ActionLeaf

enum Step {
    EXPLODE,           # 爆炸动画 + 开启 realhurtbox
    REPAIR,            # 修复动画（期间核心可被 ghostfist 攻击）
    CHECK_PLAYER,      # 修复完毕 → 检测玩家是否在范围内
    DASH_TO_PLAYER,    # 向玩家方向冲刺（蓄力→dash_go→dash_loop移动）
    POST_DASH_WAIT,    # 冲刺到达后等待 0.7s
    DASH_BACK,         # 向冲刺前位置冲回（直接 dash_loop，跳过蓄力）
    WIND_UP,           # 收招动画
    RETURN_HOME,       # 飞回母体
    DONE
}

var _step: int = Step.EXPLODE
var _dash_origin: Vector2 = Vector2.ZERO
var _dash_target: Vector2 = Vector2.ZERO
var _wait_end: float = 0.0

func before_run(actor: Node, _bb: Blackboard) -> void:
    _step = Step.EXPLODE
    var boss := actor as BossGhostWitch
    if boss: boss._baby_dash_go_triggered = false

func tick(actor: Node, blackboard: Blackboard) -> int:
    var boss := actor as BossGhostWitch
    if boss == null: return FAILURE

    match _step:
        Step.EXPLODE:
            return _tick_explode(boss)
        Step.REPAIR:
            return _tick_repair(boss)
        Step.CHECK_PLAYER:
            return _tick_check_player(boss)
        Step.DASH_TO_PLAYER:
            return _tick_dash(boss, true)
        Step.POST_DASH_WAIT:
            return _tick_wait(boss)
        Step.DASH_BACK:
            return _tick_dash(boss, false)
        Step.WIND_UP:
            return _tick_wind_up(boss)
        Step.RETURN_HOME:
            return _tick_return(boss)
    return FAILURE

func _tick_explode(boss: BossGhostWitch) -> int:
    if boss.baby_state != BossGhostWitch.BabyState.EXPLODED:
        return RUNNING
    boss.baby_anim_play(&"baby/explode", false)
    # Spine 事件 "explode_hitbox_on" → 开启 BabyExplosionArea 范围伤害
    # Spine 事件 "explode_hitbox_off" → 关闭
    # Spine 事件 "realhurtbox_on" → boss._set_baby_realhurtbox(true)
    if boss.baby_anim_is_finished(&"baby/explode"):
        boss.baby_state = BossGhostWitch.BabyState.REPAIRING
        _step = Step.REPAIR
    return RUNNING

func _tick_repair(boss: BossGhostWitch) -> int:
    boss.baby_anim_play(&"baby/repair", false)
    # 修复期间 realhurtbox 保持开启，ghostfist 可以攻击核心
    if boss.baby_anim_is_finished(&"baby/repair"):
        # Spine 事件 "realhurtbox_off" → boss._set_baby_realhurtbox(false)
        # 修复完毕，核心关闭，恢复不可打中状态
        _step = Step.CHECK_PLAYER
    return RUNNING

func _tick_check_player(boss: BossGhostWitch) -> int:
    # 检测玩家是否在 BabyDetectArea 范围内
    var player_in_range: bool = false
    for body in boss._baby_detect_area.get_overlapping_bodies():
        if body.is_in_group("player"):
            player_in_range = true
            break

    if player_in_range:
        _dash_origin = boss._baby_statue.global_position
        var player := boss.get_priority_attack_target()
        _dash_target = player.global_position if player != null else _dash_origin
        boss.baby_state = BossGhostWitch.BabyState.DASHING
        boss._baby_dash_go_triggered = false
        _step = Step.DASH_TO_PLAYER
    else:
        # 玩家不在范围内，跳过冲刺，直接收招返航
        boss.baby_state = BossGhostWitch.BabyState.WINDING_UP
        _step = Step.WIND_UP
    return RUNNING

func _tick_dash(boss: BossGhostWitch, to_player: bool) -> int:
    var target := _dash_target if to_player else _dash_origin
    var baby := boss._baby_statue

    if to_player:
        # 冲刺去：先播蓄力动画，等 dash_go 事件后切到 dash_loop
        if not boss._baby_dash_go_triggered:
            boss.baby_anim_play(&"baby/dash", false)
            # Spine 事件 "dash_go" 触发前只播蓄力，不移动
            return RUNNING
        # dash_go 已触发，切到冲刺循环动画
        boss.baby_anim_play(&"baby/dash_loop", true)
    else:
        # 冲刺回：跳过蓄力，直接播冲刺循环动画
        boss.baby_anim_play(&"baby/dash_loop", true)

    # Spine 事件 "dash_hitbox_on" → 开启 BabyAttackArea
    var dir := sign(target.x - baby.global_position.x)
    baby.global_position.x += dir * boss.baby_dash_speed * get_physics_process_delta_time()

    # 冲刺期间检测碰撞伤害
    for body in boss._baby_attack_area.get_overlapping_bodies():
        if body.is_in_group("player") and body.has_method("apply_damage"):
            body.call("apply_damage", 1, baby.global_position)

    if abs(target.x - baby.global_position.x) < 10.0:
        baby.global_position.x = target.x
        boss._baby_dash_go_triggered = false  # 重置
        if to_player:
            _wait_end = Time.get_ticks_msec() + boss.baby_post_dash_wait * 1000.0
            boss.baby_state = BossGhostWitch.BabyState.POST_DASH_WAIT
            _step = Step.POST_DASH_WAIT
        else:
            boss.baby_state = BossGhostWitch.BabyState.WINDING_UP
            _step = Step.WIND_UP
    return RUNNING

func _tick_wait(boss: BossGhostWitch) -> int:
    boss.baby_anim_play(&"baby/idle", true)
    if Time.get_ticks_msec() >= _wait_end:
        boss.baby_state = BossGhostWitch.BabyState.DASHING
        _step = Step.DASH_BACK
    return RUNNING

func _tick_wind_up(boss: BossGhostWitch) -> int:
    boss.baby_anim_play(&"baby/wind_up", false)
    if boss.baby_anim_is_finished(&"baby/wind_up"):
        boss.baby_state = BossGhostWitch.BabyState.RETURNING
        _step = Step.RETURN_HOME
    return RUNNING

func _tick_return(boss: BossGhostWitch) -> int:
    boss.baby_anim_play(&"baby/return", true)
    var target_pos := boss._mark_hug.global_position
    var baby := boss._baby_statue
    var dir := (target_pos - baby.global_position).normalized()
    baby.global_position += dir * boss.baby_return_speed * get_physics_process_delta_time()

    if baby.global_position.distance_to(target_pos) < 10.0:
        baby.global_position = target_pos
        boss.baby_state = BossGhostWitch.BabyState.IN_HUG
        boss.anim_play(&"phase1/catch_baby", false)
        return SUCCESS
    return RUNNING

func interrupt(actor: Node, blackboard: Blackboard) -> void:
    _step = Step.EXPLODE
    var boss := actor as BossGhostWitch
    if boss:
        boss._baby_dash_go_triggered = false
        boss._set_hitbox_enabled(boss._baby_attack_area, false)
        boss._set_hitbox_enabled(boss._baby_explosion_area, false)
        boss._set_baby_realhurtbox(false)
    super(actor, blackboard)
```

#### ActSlowMoveToPlayer（缓慢移动兜底）

```gdscript
class_name ActSlowMoveToPlayer extends ActionLeaf

func tick(actor: Node, blackboard: Blackboard) -> int:
    var boss := actor as BossGhostWitch
    if boss == null: return FAILURE
    var player := boss.get_priority_attack_target()
    if player == null: return RUNNING

    var h_dist := abs(player.global_position.x - actor.global_position.x)
    if h_dist < 20.0:
        actor.velocity.x = 0.0
        boss.anim_play(&"phase1/idle", true)
    else:
        var dir := signf(player.global_position.x - actor.global_position.x)
        actor.velocity.x = dir * boss.slow_move_speed
        boss.face_toward(player)
        boss.anim_play(&"phase1/walk", true)
    return RUNNING  # 永远 RUNNING，让 SelectorReactive 重评估
```

---

### 8.3 Phase 2 ActionLeaf

#### ActScytheSlash（镰刀斩）

```gdscript
class_name ActScytheSlash extends ActionLeaf

enum Step { PLAY, WAIT, DONE }
var _step: int = Step.PLAY

func before_run(actor: Node, _bb: Blackboard) -> void:
    _step = Step.PLAY

func tick(actor: Node, blackboard: Blackboard) -> int:
    var boss := actor as BossGhostWitch
    if boss == null: return FAILURE

    match _step:
        Step.PLAY:
            var player := boss.get_priority_attack_target()
            if player: boss.face_toward(player)
            boss.anim_play(&"phase2/scythe_slash", false)
            _step = Step.WAIT
            return RUNNING
        Step.WAIT:
            # Spine 事件 "scythe_hitbox_on" / "scythe_hitbox_off" 驱动伤害检测
            if boss.anim_is_finished(&"phase2/scythe_slash"):
                _set_cooldown(actor, blackboard, "cd_scythe", boss.scythe_slash_cooldown)
                return SUCCESS
            return RUNNING
    return FAILURE

func _set_cooldown(actor: Node, bb: Blackboard, key: String, cd: float) -> void:
    var actor_id := str(actor.get_instance_id())
    bb.set_value(key, Time.get_ticks_msec() + cd * 1000.0, actor_id)

func interrupt(actor: Node, blackboard: Blackboard) -> void:
    _step = Step.PLAY
    super(actor, blackboard)
```

#### ActTombstoneDrop（飞天砸落 — 攻击流3）

```gdscript
## 起手施法 → 瞬移到玩家头上 → 渐显 → 悬停 → 幽灵投掷 → 下落 → 落地冲击 → 僵直
class_name ActTombstoneDrop extends ActionLeaf

enum Step {
    CAST,           # 地面起手施法动画
    TELEPORT,       # 施法播完 → 瞬移到目标位置
    APPEAR,         # 在空中渐显（慢慢出现）
    HOVER,          # 空中静止悬停（短暂压迫感）
    THROW,          # 被幽灵向下投掷的瞬间（发力表现）
    FALLING,        # 高速下落循环
    LAND,           # 砸到地面（冲击 + 范围伤害）
    STAGGER,        # 僵直
}

var _step: int = Step.CAST
var _target_pos: Vector2 = Vector2.ZERO
var _fall_timer: float = 0.0
var _fall_speed: float = 0.0
var _hover_end: float = 0.0
var _stagger_end: float = 0.0
var _hitbox_frame_count: int = 0  # 落地伤害帧计数（替代 await）

func before_run(actor: Node, _bb: Blackboard) -> void:
    _step = Step.CAST
    _hitbox_frame_count = 0

func tick(actor: Node, blackboard: Blackboard) -> int:
    var boss := actor as BossGhostWitch
    if boss == null: return FAILURE
    var dt := get_physics_process_delta_time()

    match _step:
        Step.CAST:
            boss.anim_play(&"phase2/tombstone_cast", false)
            var player := boss.get_priority_attack_target()
            if player == null: return FAILURE
            var offset_x := boss.tombstone_offset_x_range * (1.0 if randf() > 0.5 else -1.0)
            _target_pos = Vector2(
                player.global_position.x + offset_x,
                player.global_position.y - boss.tombstone_offset_y
            )
            _step = Step.TELEPORT
            return RUNNING

        Step.TELEPORT:
            if boss.anim_is_finished(&"phase2/tombstone_cast"):
                actor.global_position = _target_pos
                actor.velocity = Vector2.ZERO
                _step = Step.APPEAR
            return RUNNING

        Step.APPEAR:
            boss.anim_play(&"phase2/tombstone_appear", false)
            if boss.anim_is_finished(&"phase2/tombstone_appear"):
                _step = Step.HOVER
                _hover_end = Time.get_ticks_msec() + boss.tombstone_hover_duration * 1000.0
            return RUNNING

        Step.HOVER:
            boss.anim_play(&"phase2/tombstone_hover", true)
            if Time.get_ticks_msec() >= _hover_end:
                _step = Step.THROW
            return RUNNING

        Step.THROW:
            boss.anim_play(&"phase2/tombstone_throw", false)
            if boss.anim_is_finished(&"phase2/tombstone_throw"):
                _fall_timer = 0.0
                _fall_speed = 0.0
                _step = Step.FALLING
            return RUNNING

        Step.FALLING:
            boss.anim_play(&"phase2/tombstone_fall", true)
            _fall_timer += dt
            var t_ratio := clampf(_fall_timer / boss.tombstone_fall_duration, 0.0, 1.0)
            var eased := t_ratio * t_ratio
            _fall_speed = eased * 2000.0
            actor.velocity.y = _fall_speed

            for body in boss._ground_hitbox.get_overlapping_bodies():
                if body.is_in_group("player") and body.has_method("apply_damage"):
                    body.call("apply_damage", 1, actor.global_position)

            if actor.is_on_floor():
                _step = Step.LAND
                _hitbox_frame_count = 0
            return RUNNING

        Step.LAND:
            actor.velocity = Vector2.ZERO
            boss.anim_play(&"phase2/tombstone_land", false)
            if _hitbox_frame_count == 0:
                boss._set_hitbox_enabled(boss._ground_hitbox, true)
            elif _hitbox_frame_count >= 2:
                boss._set_hitbox_enabled(boss._ground_hitbox, false)
                _stagger_end = Time.get_ticks_msec() + boss.tombstone_stagger_duration * 1000.0
                _step = Step.STAGGER
            _hitbox_frame_count += 1
            return RUNNING

        Step.STAGGER:
            if Time.get_ticks_msec() >= _stagger_end:
                _set_cooldown(actor, blackboard, "cd_tombstone", boss.tombstone_drop_cooldown)
                return SUCCESS
            return RUNNING
    return FAILURE

func _set_cooldown(actor: Node, bb: Blackboard, key: String, cd: float) -> void:
    bb.set_value(key, Time.get_ticks_msec() + cd * 1000.0, str(actor.get_instance_id()))

func interrupt(actor: Node, blackboard: Blackboard) -> void:
    _step = Step.CAST
    _hitbox_frame_count = 0
    var boss := actor as BossGhostWitch
    if boss:
        boss._set_hitbox_enabled(boss._ground_hitbox, false)
        actor.velocity = Vector2.ZERO
    super(actor, blackboard)
```

#### ActUndeadWind（亡灵气流 — 攻击流4）

```gdscript
## 7秒内逐渐生成10只幽灵 + 随机时间生成1只精英亡灵
## 期间 realhurtbox 不可攻击
class_name ActUndeadWind extends ActionLeaf

enum Step { CAST_ENTER, SPAWNING, CAST_END, DONE }
var _step: int = Step.CAST_ENTER
var _spawn_timer: float = 0.0
var _spawn_count: int = 0
var _elite_spawned: bool = false
var _elite_spawn_time: float = 0.0  # 随机决定精英生成时机
var _type_cycle: int = 0  # 0,1,2 循环 → type1,type2,type3

func before_run(actor: Node, _bb: Blackboard) -> void:
    _step = Step.CAST_ENTER
    _spawn_timer = 0.0
    _spawn_count = 0
    _elite_spawned = false
    _elite_spawn_time = randf_range(1.0, 6.0)
    _type_cycle = 0

func tick(actor: Node, blackboard: Blackboard) -> int:
    var boss := actor as BossGhostWitch
    if boss == null: return FAILURE
    var dt := get_physics_process_delta_time()

    match _step:
        Step.CAST_ENTER:
            boss.anim_play(&"phase2/undead_wind_cast", false)
            boss._set_realhurtbox_enabled(false)  # 期间不可攻击
            _step = Step.SPAWNING
            return RUNNING
        Step.SPAWNING:
            boss.anim_play(&"phase2/undead_wind_loop", true)
            _spawn_timer += dt
            # 加速度生成：间隔随时间缩短
            var interval := lerpf(1.2, 0.3, clampf(_spawn_timer / boss.undead_wind_spawn_duration, 0.0, 1.0))
            # 简化：用计数和时间判断是否该生成下一只
            if _spawn_count < boss.undead_wind_total_count:
                var expected_count := int(_spawn_timer / interval)
                if expected_count > _spawn_count:
                    _spawn_wraith(boss)
                    _spawn_count += 1

            # 精英亡灵
            if not _elite_spawned and _spawn_timer >= _elite_spawn_time:
                _spawn_elite(boss)
                _elite_spawned = true

            if _spawn_timer >= boss.undead_wind_spawn_duration:
                _step = Step.CAST_END
            return RUNNING
        Step.CAST_END:
            boss.anim_play(&"phase2/undead_wind_end", false)
            boss._set_realhurtbox_enabled(true)  # 恢复可攻击
            if boss.anim_is_finished(&"phase2/undead_wind_end"):
                _set_cooldown(actor, blackboard, "cd_wind", boss.undead_wind_cooldown)
                return SUCCESS
            return RUNNING
    return FAILURE

func _spawn_wraith(boss: BossGhostWitch) -> void:
    var wraith: Node2D = boss._ghost_wraith_scene.instantiate()
    wraith.add_to_group("ghost_wraith")
    # 设置 type (1,2,3 循环)
    var wraith_type := (_type_cycle % 3) + 1
    _type_cycle += 1
    if wraith.has_method("setup"):
        var player := boss.get_priority_attack_target()
        wraith.call("setup", wraith_type, player, boss.global_position)
    wraith.global_position = boss.global_position
    boss.get_parent().add_child(wraith)

func _spawn_elite(boss: BossGhostWitch) -> void:
    var elite: Node2D = boss._ghost_elite_scene.instantiate()
    elite.add_to_group("ghost_elite")
    if elite.has_method("setup"):
        var player := boss.get_priority_attack_target()
        elite.call("setup", player, boss)  # 传入 boss 引用，被击杀时扣 boss HP
    elite.global_position = boss.global_position
    boss.get_parent().add_child(elite)

func _set_cooldown(actor: Node, bb: Blackboard, key: String, cd: float) -> void:
    bb.set_value(key, Time.get_ticks_msec() + cd * 1000.0, str(actor.get_instance_id()))

func interrupt(actor: Node, blackboard: Blackboard) -> void:
    _step = Step.CAST_ENTER
    var boss := actor as BossGhostWitch
    if boss: boss._set_realhurtbox_enabled(true)
    super(actor, blackboard)
```

#### ActGhostTug（幽灵拔河 — 攻击流2）

```gdscript
## 召唤幽灵拔河拉玩家到近身 → 镰刀斩检测区 → 吸力停 → 镰刀斩
## 可被 ghostfist 打断
class_name ActGhostTug extends ActionLeaf

enum Step { CAST, PULLING, SCYTHE_SLASH, DONE }
var _step: int = Step.CAST
var _tug_instance: Node2D = null

func before_run(actor: Node, _bb: Blackboard) -> void:
    _step = Step.CAST

func tick(actor: Node, blackboard: Blackboard) -> int:
    var boss := actor as BossGhostWitch
    if boss == null: return FAILURE

    match _step:
        Step.CAST:
            boss.anim_play(&"phase2/ghost_tug_cast", false)
            # Spine 事件 "tug_spawn" 时生成拔河实例
            var player := boss.get_priority_attack_target()
            if player == null: return FAILURE
            _tug_instance = boss._ghost_tug_scene.instantiate()
            _tug_instance.add_to_group("ghost_tug")
            if _tug_instance.has_method("setup"):
                _tug_instance.call("setup", player, boss, boss.ghost_tug_pull_speed)
            player.add_child(_tug_instance)  # 绑定到玩家的 center3 位置
            _step = Step.PULLING
            return RUNNING
        Step.PULLING:
            boss.anim_play(&"phase2/ghost_tug_loop", true)
            # 检查拔河是否被打断（ghostfist 击中拔河检测点）
            if _tug_instance == null or not is_instance_valid(_tug_instance):
                # 被打断
                _set_cooldown(actor, blackboard, "cd_tug", boss.ghost_tug_cooldown)
                return SUCCESS  # 返回 SUCCESS 让 Selector 重评估
            # 检查玩家是否到达镰刀检测区
            if _player_in_scythe_area(boss):
                _destroy_tug()
                _step = Step.SCYTHE_SLASH
            return RUNNING
        Step.SCYTHE_SLASH:
            boss.anim_play(&"phase2/scythe_slash", false)
            if boss.anim_is_finished(&"phase2/scythe_slash"):
                _set_cooldown(actor, blackboard, "cd_tug", boss.ghost_tug_cooldown)
                _set_cooldown(actor, blackboard, "cd_scythe", boss.scythe_slash_cooldown)
                return SUCCESS
            return RUNNING
    return FAILURE

func _player_in_scythe_area(boss: BossGhostWitch) -> bool:
    for body in boss._scythe_detect_area.get_overlapping_bodies():
        if body.is_in_group("player"):
            return true
    return false

func _destroy_tug() -> void:
    if _tug_instance != null and is_instance_valid(_tug_instance):
        _tug_instance.queue_free()
        _tug_instance = null

func _set_cooldown(actor: Node, bb: Blackboard, key: String, cd: float) -> void:
    bb.set_value(key, Time.get_ticks_msec() + cd * 1000.0, str(actor.get_instance_id()))

func interrupt(actor: Node, blackboard: Blackboard) -> void:
    _destroy_tug()
    _step = Step.CAST
    super(actor, blackboard)
```

#### ActSpawnGhostBomb（被动：生成自爆幽灵）

```gdscript
class_name ActSpawnGhostBomb extends ActionLeaf

func tick(actor: Node, blackboard: Blackboard) -> int:
    var boss := actor as BossGhostWitch
    if boss == null: return FAILURE
    var bomb: Node2D = boss._ghost_bomb_scene.instantiate()
    bomb.add_to_group("ghost_bomb")
    if bomb.has_method("setup"):
        var player := boss.get_priority_attack_target()
        bomb.call("setup", player, boss.ghost_bomb_light_energy)
    bomb.global_position = boss.global_position
    boss.get_parent().add_child(bomb)
    _set_cooldown(actor, blackboard, "cd_bomb", boss.ghost_bomb_interval)
    return SUCCESS  # 立即完成，不是 RUNNING

func _set_cooldown(actor: Node, bb: Blackboard, key: String, cd: float) -> void:
    bb.set_value(key, Time.get_ticks_msec() + cd * 1000.0, str(actor.get_instance_id()))
```

#### ActMoveTowardPlayer（Phase 2 移动兜底）

```gdscript
class_name ActMoveTowardPlayer extends ActionLeaf

@export var move_speed: float = 80.0

func tick(actor: Node, _bb: Blackboard) -> int:
    var boss := actor as BossGhostWitch
    if boss == null: return FAILURE
    var player := boss.get_priority_attack_target()
    if player == null:
        actor.velocity.x = 0.0
        return RUNNING

    var h_dist := abs(player.global_position.x - actor.global_position.x)
    if h_dist < 30.0:
        actor.velocity.x = 0.0
        boss.anim_play(&"phase2/idle", true)
    else:
        var dir := signf(player.global_position.x - actor.global_position.x)
        actor.velocity.x = dir * move_speed
        boss.face_toward(player)
        boss.anim_play(&"phase2/walk", true)
    return RUNNING
```

---

## 9. 子实例场景设计

### 9.1 GhostTug.tscn（幽灵拔河）

**节点结构：**
```
GhostTug (Node2D)  # ghost_tug.gd
├── SpineSprite    # 幽灵拔河动画
└── HitArea (Area2D)  # ghostfist 打断用检测区
    └── CollisionShape2D
```

**动画清单：**

| 动画名 | loop | 用途 |
|---|---|---|
| `appear` | false | 出场渐显（Spine 动画内控制透明度从 0→1）|
| `move_loop` | true | 拉拽中循环 |
| `hit` | false | 被 ghostfist 打中后受击 + 渐隐消失（Spine 动画内控制透明度 1→0），播完后销毁节点 |

**出场和受击消失的透明度全部由 Spine 动画控制，不用代码 tween。**

**ghost_tug.gd 核心逻辑：**

```gdscript
extends Node2D

var _player: Node2D = null
var _boss: Node2D = null
var _pull_speed: float = 400.0
var _dying: bool = false
var _appeared: bool = false

func setup(player: Node2D, boss: Node2D, pull_speed: float) -> void:
    _player = player
    _boss = boss
    _pull_speed = pull_speed

func _ready() -> void:
    # 出场动画（Spine 内控制透明度渐显）
    _play_anim(&"appear", false)

    # 连接 Spine 动画完成信号
    var spine: Node = get_node_or_null("SpineSprite")
    if spine and spine.has_signal("animation_event"):
        spine.animation_event.connect(_on_spine_event)
    if spine and spine.has_signal("animation_completed"):
        spine.animation_completed.connect(_on_anim_completed_raw)

    # HitArea 被 ghostfist 击中
    $HitArea.area_entered.connect(_on_hit)

func _on_anim_completed_raw(_spine_sprite, _track_entry) -> void:
    # appear 播完 → 切到 move_loop
    if not _appeared and not _dying:
        _appeared = true
        _play_anim(&"move_loop", true)
        return
    # hit 播完 → 销毁
    if _dying:
        queue_free()

func _on_spine_event(a1, a2, a3, a4) -> void:
    if _dying: return
    var event_name := _extract_event_name(a1, a2, a3, a4)
    if event_name == &"move":
        _pull_player_toward_boss()

func _pull_player_toward_boss() -> void:
    if _player == null or _boss == null: return
    if not is_instance_valid(_player) or not is_instance_valid(_boss): return
    var dir_x := signf(_boss.global_position.x - _player.global_position.x)
    _player.velocity.x = dir_x * _pull_speed
    if _player.has_method("set_external_control_frozen"):
        _player.call("set_external_control_frozen", true)

func _on_hit(area: Area2D) -> void:
    if _dying: return
    if not area.is_in_group("ghost_fist_hitbox"): return
    _dying = true
    _release_player()
    # 播放受击 + 渐隐动画（Spine 内控制透明度），播完后 _on_anim_completed_raw 触发 queue_free
    _play_anim(&"hit", false)

func _release_player() -> void:
    if _player and is_instance_valid(_player) and _player.has_method("set_external_control_frozen"):
        _player.call("set_external_control_frozen", false)

func _exit_tree() -> void:
    _release_player()

func _extract_event_name(a1, a2, a3, a4) -> StringName:
    for a in [a1, a2, a3, a4]:
        if a is Object and a.has_method("get_data"):
            var data = a.get_data()
            if data != null and data.has_method("get_event_name"):
                return StringName(data.get_event_name())
    return &""

func _play_anim(_name: StringName, _loop: bool) -> void:
    pass  # 实际走 AnimDriverSpine / SpineSprite
```

### 9.2 GhostBomb.tscn（自爆幽灵）

**节点结构：**
```
GhostBomb (CharacterBody2D)  # ghost_bomb.gd
├── SpineSprite
├── HurtArea (Area2D)    # 被 ghostfist 消灭
│   └── CollisionShape2D
├── ExplosionArea (Area2D)  # 自爆伤害区
│   └── CollisionShape2D
└── LightArea (Area2D)      # 自爆光照区（范围比伤害区大）
    └── CollisionShape2D
```

**动画清单：**

| 动画名 | loop | 事件 | 用途 |
|---|---|---|---|
| `appear` | false | — | 出现动画 |
| `move` | true | — | S 形移动中 |
| `explode` | false | `explosion_hitbox_on`、`explosion_hitbox_off`、`light_emit` | 自爆（伤害区和光照区分开触发）|

**核心逻辑要点：**
- 出现后播放 `appear`，播完切 `move`
- S 形移动：每 2 秒检测玩家位置，用 `sin(time * frequency) * amplitude` 在 X 轴叠加蛇形偏移
- 触碰玩家 → 1 秒延迟自爆 → 播放 `explode` → Spine 事件控制伤害区和光照区
- `explosion_hitbox_on`/`off`：控制 ExplosionArea（伤害）
- `light_emit`：触发光照（EventBus 或 LightArea），光照能量 +5
- 伤害区和光照区是分开的 Area2D，光照区范围更大
- 被 ghostfist 打中 → 直接 `queue_free()`（不播爆炸，直接消失）
- Phase 2 结束时 Boss 调用 `get_tree().call_group("ghost_bomb", "queue_free")` 清除全部

**ghost_bomb.gd 核心代码示例：**

```gdscript
extends CharacterBody2D

var _player: Node2D = null
var _light_energy: float = 5.0
var _move_speed: float = 60.0
var _track_interval: float = 2.0
var _track_timer: float = 0.0
var _target_pos: Vector2 = Vector2.ZERO
var _time: float = 0.0
var _exploding: bool = false
var _appeared: bool = false

@export var s_curve_amplitude: float = 40.0
@export var s_curve_frequency: float = 2.0
@export var explode_delay: float = 1.0

func setup(player: Node2D, light_energy: float) -> void:
    _player = player
    _light_energy = light_energy

func _ready() -> void:
    add_to_group("ghost_bomb")
    _play_anim(&"appear", false)
    # 连接信号
    $HurtArea.area_entered.connect(_on_ghostfist_hit)
    $ExplosionArea.body_entered.connect(_on_touch_player)
    var spine: Node = get_node_or_null("SpineSprite")
    if spine and spine.has_signal("animation_completed"):
        spine.animation_completed.connect(_on_anim_completed_raw)
    if spine and spine.has_signal("animation_event"):
        spine.animation_event.connect(_on_spine_event)

func _on_anim_completed_raw(_ss, _te) -> void:
    if not _appeared and not _exploding:
        _appeared = true
        _update_target()
        _play_anim(&"move", true)
        return
    if _exploding:
        queue_free()

func _physics_process(dt: float) -> void:
    if _exploding or not _appeared: return
    _time += dt
    _track_timer += dt
    if _track_timer >= _track_interval:
        _track_timer = 0.0
        _update_target()
    # S 形移动
    var dir := (_target_pos - global_position).normalized()
    var s_offset := sin(_time * s_curve_frequency) * s_curve_amplitude
    velocity = dir * _move_speed + Vector2(s_offset, 0)
    move_and_slide()

func _on_touch_player(body: Node2D) -> void:
    if _exploding: return
    if not body.is_in_group("player"): return
    _start_explode()

func _start_explode() -> void:
    _exploding = true
    velocity = Vector2.ZERO
    # 1秒延迟后播放爆炸动画
    await get_tree().create_timer(explode_delay).timeout
    _play_anim(&"explode", false)

func _on_spine_event(a1, a2, a3, a4) -> void:
    var event_name := _extract_event_name(a1, a2, a3, a4)
    match event_name:
        &"explosion_hitbox_on":
            _set_area_enabled($ExplosionArea, true)
        &"explosion_hitbox_off":
            _set_area_enabled($ExplosionArea, false)
        &"light_emit":
            # 释放光照能量（与 lightflower 同机制）
            if EventBus:
                EventBus.emit_signal("healing_burst", _light_energy)

func _on_ghostfist_hit(area: Area2D) -> void:
    if area.is_in_group("ghost_fist_hitbox"):
        queue_free()

func _update_target() -> void:
    if _player and is_instance_valid(_player):
        _target_pos = _player.global_position

func _set_area_enabled(area: Area2D, enabled: bool) -> void:
    area.set_deferred("monitoring", enabled)
    for child in area.get_children():
        if child is CollisionShape2D:
            child.set_deferred("disabled", not enabled)

func _extract_event_name(a1, a2, a3, a4) -> StringName:
    for a in [a1, a2, a3, a4]:
        if a is Object and a.has_method("get_data"):
            var data = a.get_data()
            if data != null and data.has_method("get_event_name"):
                return StringName(data.get_event_name())
    return &""

func _play_anim(_name: StringName, _loop: bool) -> void:
    pass  # 实际走 AnimDriverSpine / SpineSprite
```

### 9.3 GhostWraith.tscn（亡灵气流幽灵，3 型合一）

**节点结构：**
```
GhostWraith (Node2D)  # ghost_wraith.gd
├── SpineSprite
└── HitArea (Area2D)   # 碰到玩家伤害 + 被 ghostfist 检测
    └── CollisionShape2D
```

**核心逻辑要点：**
- `setup(type: int, player: Node2D, spawn_pos: Vector2)`：type 决定播放 `type1/move`、`type2/move`、`type3/move`
- X 轴向玩家方向平移，速度偏慢（~80px/s）
- 碰到玩家 → `player.apply_damage(1, global_position)`
- 被 ghostfist 打中 → 播放对应 type 的死亡动画（`type1/death`、`type2/death`、`type3/death`）→ 动画播完后 `queue_free()`
- 最多存活 10 秒 → 自动 `queue_free()`

**动画清单：**

| 动画名 | loop | 用途 |
|---|---|---|
| `type1/move` | true | 第1型移动 |
| `type2/move` | true | 第2型移动 |
| `type3/move` | true | 第3型移动 |
| `type1/death` | false | 第1型被打消失 |
| `type2/death` | false | 第2型被打消失 |
| `type3/death` | false | 第3型被打消失 |

**被打消失代码示例：**

```gdscript
var _type: int = 1
var _dying: bool = false

func _on_hit_by_ghostfist(area: Area2D) -> void:
    if _dying: return
    if not area.is_in_group("ghost_fist_hitbox"): return
    _dying = true
    set_physics_process(false)  # 停止移动
    var death_anim := StringName("type%d/death" % _type)
    _play_anim(death_anim, false)

func _on_death_anim_finished() -> void:
    queue_free()
```

### 9.4 GhostElite.tscn（精英亡灵）

**节点结构：**
```
GhostElite (Node2D)  # ghost_elite.gd
├── SpineSprite
├── HitArea (Area2D)     # 被 ghostfist 击杀
│   └── CollisionShape2D
└── AttackArea (Area2D)  # 范围挥击
    └── CollisionShape2D
```

**核心逻辑要点：**
- HP = 1，被 ghostfist 打中 → 播放 `death` 动画 → 动画播完后 `queue_free()` + 调用 `boss.apply_real_damage(1)` 扣 Boss 血
- 向玩家方向平移（同 GhostWraith 速度），播放 `move` 动画
- 检测到玩家在范围内时发动挥击（cd=1s），播放 `attack` 动画
- 挥击：Spine 事件 `attack_hitbox_on` / `attack_hitbox_off` 控制 AttackArea 启闭
- 一次攻击流中只能生成 1 只

**动画清单：**

| 动画名 | loop | 事件 | 用途 |
|---|---|---|---|
| `move` | true | — | 向玩家移动 |
| `attack` | false | `attack_hitbox_on`、`attack_hitbox_off` | 范围挥击 |
| `death` | false | — | 被 ghostfist 打中后死亡消失 |

**核心代码示例：**

```gdscript
extends Node2D

var _player: Node2D = null
var _boss: Node2D = null
var _dying: bool = false
var _attacking: bool = false
var _attack_cd_end: float = 0.0
var _move_speed: float = 80.0
var _detect_range: float = 100.0

func setup(player: Node2D, boss: Node2D) -> void:
    _player = player
    _boss = boss

func _physics_process(dt: float) -> void:
    if _dying or _attacking: return
    if _player == null or not is_instance_valid(_player): return

    var h_dist := abs(global_position.x - _player.global_position.x)

    # 检测到玩家在范围内 → 挥击
    if h_dist <= _detect_range and Time.get_ticks_msec() >= _attack_cd_end:
        _attacking = true
        _play_anim(&"attack", false)
        return

    # 向玩家移动
    var dir := signf(_player.global_position.x - global_position.x)
    global_position.x += dir * _move_speed * dt
    _play_anim(&"move", true)

func _on_attack_anim_finished() -> void:
    _attacking = false
    _attack_cd_end = Time.get_ticks_msec() + 1000.0  # 1s cd

func _on_hit_by_ghostfist(area: Area2D) -> void:
    if _dying: return
    if not area.is_in_group("ghost_fist_hitbox"): return
    _dying = true
    set_physics_process(false)
    _play_anim(&"death", false)

func _on_death_anim_finished() -> void:
    if _boss and is_instance_valid(_boss):
        _boss.apply_real_damage(1)
    queue_free()
```

---

## 10. Phase 1→2 过渡流程

### 10.1 触发条件

`hp <= phase2_hp_threshold` (hp <= 20) 时调用 `_begin_phase_transition(Phase.PHASE2)`。

### 10.2 过渡步骤（时序严格）

```
1. hp_locked = true，_phase_transitioning = true
2. 中断当前攻击流（行为树检测 _phase_transitioning → ActWaitTransition 接管）
3. 如果婴儿石像不在怀中（baby_state != IN_HUG）：
   → 立即中断攻击流，婴儿播放 baby/phase1_to_phase2
   → 等待 baby/phase1_to_phase2 播完
   → baby_state = HALO
   → BabyBodyBox disabled（永久）
   → BabyRealHurtbox enabled（永久）
   → 婴儿飞向 Mark2D_Hale 位置
   → 到达后 → 步骤 4
4. 如果婴儿在怀中：
   → 婴儿直接播放 baby/phase1_to_phase2
   → 同步骤 3 的 box 切换
   → 婴儿移动到 Mark2D_Hale
   → 到达后 → 步骤 5
5. 光环到达 hale 位置后：
   → 魔女石像播放 phase1/phase1_to_phase2
   → 播完后：魔女动画切到 phase2/idle
   → BabyStatue.visible = false（光环视觉已包含在魔女 Phase2 动画中）
   → RealHurtbox（Boss 本体的）绑定到魔女 hale 骨骼，enabled
   → current_phase = Phase.PHASE2
   → _phase_transitioning = false
   → hp_locked = false
```

### 10.3 ActWaitTransition（变身等待 Action）

```gdscript
class_name ActWaitTransition extends ActionLeaf

func tick(actor: Node, _bb: Blackboard) -> int:
    var boss := actor as BossGhostWitch
    if boss == null: return FAILURE
    if boss._phase_transitioning:
        return RUNNING  # 变身动画还没播完，保持 RUNNING
    return FAILURE  # 变身结束，让 CondPhaseTransitioning 失败，退出此分支
```

---

> Spine 动画事件清单和攻击参数总表已统合至第 19、20 节（含全三阶段）。

---

## 11. Phase 2→3 过渡流程

### 13.1 触发条件

`hp <= phase3_hp_threshold`（hp <= 10）时调用 `_begin_phase_transition(Phase.PHASE3)`。

### 13.2 过渡描述

> 石像全部碎掉，光环掉下来，鬼魂在旁边趴着，看着它们曾经的主人。突然，鬼魂被光环绑住抓住。
> 卷入到巨大的漩涡中，与墓碑的碎石合体后变成了带着镰刀的无头骑士。它拽下了光环，变成了自己巨大的镰刀。

### 13.3 过渡时序

```
1. hp_locked = true，_phase_transitioning = true
2. 中断当前 Phase 2 所有攻击流（行为树 ActWaitTransition 接管）
3. 清理 Phase 2 残留：
   → get_tree().call_group("ghost_bomb", "queue_free")
   → get_tree().call_group("ghost_wraith", "queue_free")
   → get_tree().call_group("ghost_elite", "queue_free")
   → get_tree().call_group("ghost_tug", "queue_free")
4. Boss 播放 phase2/phase2_to_phase3 动画
   → Spine 事件 "shatter"：视觉碎裂效果
   → Spine 事件 "phase3_ready"：动画末尾
5. 动画播完后：
   → 魔女动画切到 phase3/idle
   → RealHurtbox 保持绑定 hale 骨骼，保持 enabled（光环弱点延续）
   → current_phase = Phase.PHASE3
   → _phase_transitioning = false
   → hp_locked = false
   → _scythe_in_hand = true（镰刀在手）
```

---

## 12. Phase 3 形态概述与状态变量

**外观**：无头骑士，手持巨大镰刀（由光环变化而来）。

**核心机制**：
- `RealHurtbox` 依然绑定 hale 骨骼（头顶光环位置），是唯一弱点
- 只有 ghostfist 可造成伤害，chain 依然无效
- 镰刀可被扔出变成独立实例 `WitchScythe`；扔出期间本体禁止一切行为，只能原地待机
- 地狱之手 `HellHand` 可禁锢玩家；ghostfist 可解

**关键状态变量**（追加到 `boss_ghost_witch.gd`）：

```gdscript
# Phase 3 专用状态
var _scythe_in_hand: bool = true           # 镰刀是否在手
var _scythe_instance: Node2D = null        # 扔出的镰刀实例引用
var _scythe_recall_requested: bool = false  # 本体被打时请求镰刀回航
var _hell_hand_instance: Node2D = null     # 地狱之手实例引用
var _player_imprisoned: bool = false        # 是否检测到玩家被禁锢
```

**Phase 3 追加导出参数**：

```gdscript
# -- Phase 3 参数 --
@export var p3_move_speed: float = 120.0         # 无头骑士移动速度
@export var p3_run_speed: float = 250.0          # 奔跑斩击速度
@export var p3_dash_cooldown: float = 10.0       # 冲刺冷却
@export var p3_dash_charge_time: float = 1.0     # 冲刺蓄力时间
@export var p3_dash_speed: float = 800.0         # 冲刺速度
@export var p3_kick_cooldown: float = 1.0        # 踢人冷却
@export var p3_kick_knockback_px: float = 300.0  # 踢人弹飞距离
@export var p3_combo_cooldown: float = 1.0       # 三连斩冷却
@export var p3_combo_duration: float = 3.0       # 三连斩总持续时间
@export var p3_imprison_cooldown: float = 10.0   # 禁锢冷却
@export var p3_imprison_escape_time: float = 0.5 # 玩家逃出禁锢的窗口
@export var p3_imprison_stun_time: float = 3.0   # 禁锢僵直持续时间
@export var p3_scythe_track_interval: float = 1.0 # 镰刀每次重新检测玩家位置的间隔（秒）
@export var p3_scythe_track_count: int = 3        # 镰刀检测玩家位置的次数，完成后直线回航
@export var p3_scythe_fly_speed: float = 300.0    # 镰刀飞行速度
@export var p3_scythe_return_speed: float = 500.0 # 镰刀回航速度
@export var p3_summon_cooldown: float = 8.0      # 召唤幽灵冷却（待定）
@export var p3_summon_wave_count: int = 3        # 5秒内发动次数
@export var p3_summon_circle_count: int = 3      # 每波圆圈数（1个玩家位置+2个随机）
@export var p3_run_slash_overshoot_px: float = 200.0 # 奔跑斩击穿过玩家的距离
```

**Phase 3 追加预加载**：

```gdscript
var _witch_scythe_scene: PackedScene = preload("res://scene/enemies/boss_ghost_witch/WitchScythe.tscn")
var _hell_hand_scene: PackedScene = preload("res://scene/enemies/boss_ghost_witch/HellHand.tscn")
var _ghost_summon_scene: PackedScene = preload("res://scene/enemies/boss_ghost_witch/GhostSummon.tscn")
```

**Phase 3 追加 apply_real_damage 镰刀回航逻辑**：

```gdscript
# 在 apply_real_damage 中追加：
func apply_real_damage(amount: int) -> void:
    if hp_locked:
        _flash_once()
        return
    hp = max(hp - amount, 0)
    _flash_once()

    # Phase 3 扔镰刀期间被打 → 触发镰刀回航
    if current_phase == Phase.PHASE3 and not _scythe_in_hand:
        _scythe_recall_requested = true

    # 阶段切换检查
    if current_phase == Phase.PHASE1 and hp <= phase2_hp_threshold:
        _begin_phase_transition(Phase.PHASE2)
    elif current_phase == Phase.PHASE2 and hp <= phase3_hp_threshold:
        _begin_phase_transition(Phase.PHASE3)
    elif hp <= 0:
        _begin_death()
```

---

## 13. Phase 3 节点结构追加

以下节点追加到 `BossGhostWitch.tscn`（Phase 3 使用）：

```
BossGhostWitch (CharacterBody2D)
├── ...（Phase 1&2 节点不变）
│
├── # ===== Phase 3 追加 =====
├── KickHitbox (Area2D)             # 踢人判定，绑定 leg 骨骼
│   └── CollisionShape2D            # 默认 disabled
├── Attack1Area (Area2D)            # 三连斩第1击
│   └── CollisionShape2D            # 默认 disabled
├── Attack2Area (Area2D)            # 三连斩第2击
│   └── CollisionShape2D            # 默认 disabled
├── Attack3Area (Area2D)            # 三连斩第3击
│   └── CollisionShape2D            # 默认 disabled
└── RunSlashHitbox (Area2D)         # 奔跑斩击判定
    └── CollisionShape2D            # 默认 disabled
```

**碰撞配置（全部统一）：**

| 节点 | collision_layer | collision_mask |
|---|---|---|
| KickHitbox | `32` (hazards(6)) | `2` (PlayerBody(2)) |
| Attack1/2/3Area | `32` (hazards(6)) | `2` (PlayerBody(2)) |
| RunSlashHitbox | `32` (hazards(6)) | `2` (PlayerBody(2)) |

**骨骼绑定（_physics_process 每帧同步）：**

```gdscript
func _sync_phase3_hitboxes() -> void:
    if current_phase != Phase.PHASE3: return
    if _anim_driver == null: return
    # KickHitbox → leg 骨骼
    var leg_pos: Vector2 = _anim_driver.get_bone_world_position("leg")
    if leg_pos != Vector2.ZERO:
        _kick_hitbox.global_position = leg_pos
    # RealHurtbox → hale 骨骼（延续 Phase 2）
    var hale_pos: Vector2 = _anim_driver.get_bone_world_position("hale")
    if hale_pos != Vector2.ZERO:
        _real_hurtbox.global_position = hale_pos
```

**Boss 主脚本 Phase 3 Hitbox 管理：**

```gdscript
@onready var _kick_hitbox: Area2D = $KickHitbox
@onready var _attack1_area: Area2D = $Attack1Area
@onready var _attack2_area: Area2D = $Attack2Area
@onready var _attack3_area: Area2D = $Attack3Area
@onready var _run_slash_hitbox: Area2D = $RunSlashHitbox

func _close_all_combo_hitboxes() -> void:
    _set_hitbox_enabled(_attack1_area, false)
    _set_hitbox_enabled(_attack2_area, false)
    _set_hitbox_enabled(_attack3_area, false)

func _on_kick_hitbox_body_entered(body: Node2D) -> void:
    if not _atk_hit_window_open: return
    if body.is_in_group("player"):
        if body.has_method("apply_damage"):
            body.call("apply_damage", 1, global_position)
        if body is CharacterBody2D:
            var kb_dir := signf(body.global_position.x - global_position.x)
            if kb_dir == 0.0: kb_dir = 1.0
            body.velocity.x = kb_dir * p3_kick_knockback_px * 5.0
```

---

## 14. Phase 3 行为树

### 16.1 攻击优先级总结

```
优先级 1 (最高)：禁锢检测 → 奔跑斩击 / 追踪扔镰刀
  → 玩家被地狱之手禁锢 → Boss 立刻奔跑穿过玩家斩击
  → 若玩家在上方（跳板上）→ 跑到玩家 X 位置，向上扔镰刀追踪

优先级 2：禁锢（地狱之手）
  → 玩家在地面上 + 禁锢可用 + 镰刀在手 → 优先禁锢
  → cd=10s，全场检测

优先级 3：召唤幽灵
  → 玩家在跳板上 + ≤500px + 镰刀在手
  → 起手施法自带 combo3 攻击判定（一边召唤一边顺手砍一刀）
  → 地面出现圆圈 → 0.3s 后幽灵飞出 → 5秒内3波
  → 施法全程不可移动，维持 summon_loop 直到场上所有召唤幽灵被销毁才结束

优先级 4：冲刺
  → 300~500px + cd=10s + 镰刀在手
  → 蓄力1秒 → 快速冲刺 → 刹车减速 → 结束

优先级 5：三连斩
  → ≤200px + 玩家在上方 + 镰刀在手
  → 3秒内连续检测 attack1/attack2/attack3 区域

优先级 6：踢人
  → ≤100px + 玩家在地面 + 镰刀在手
  → cd=1s，踢中弹飞 300px

优先级 7 (兜底)：扔镰刀
  → 其他技能全部不可用 / 冷却中 + 镰刀在手
  → 无限范围，镰刀追踪砍击
  → 本体被打 → 镰刀回航 → catch_scythe → 攻击流结束 → 行为树正常重评估

镰刀不在手时的行为限制：
  → 禁止一切：不移动、不追击、不踢人、不施放任何技能
  → 仅允许：原地待机（idle_no_scythe），等待镰刀回航
  → 镰刀回航 catch_scythe 播完后 _scythe_in_hand 恢复 true，一切行为解锁

兜底：
  镰刀在手 → 缓慢向玩家移动（walk）
  镰刀不在手 → 原地待机（idle_no_scythe）
```

### 16.2 行为树结构

```
SelectorReactiveComposite [P3Selector]
│
├── SequenceReactiveComposite [P3ImprisonReactSeq]     ← 优先级 1：检测到禁锢
│   ├── CondPlayerImprisoned
│   └── SelectorComposite [P3ImprisonReactAction]
│       ├── SequenceReactiveComposite [P3RunSlashIfGround]
│       │   ├── CondPlayerOnGround
│       │   └── ActRunSlash
│       └── ActThrowScytheUpward
│
├── SequenceReactiveComposite [P3ImprisonCastSeq]      ← 优先级 2：禁锢
│   ├── CondPlayerOnGround
│   ├── CondCooldownReady (key="cd_imprison", cd=10)
│   ├── CondScytheInHand
│   └── ActCastImprison
│
├── SequenceReactiveComposite [P3SummonSeq]            ← 优先级 3：召唤幽灵
│   ├── CondPlayerOnPlatform
│   ├── CondPlayerInRange (range=500)
│   ├── CondCooldownReady (key="cd_summon", cd=p3_summon_cooldown)
│   ├── CondScytheInHand
│   └── ActSummonGhosts
│
├── SequenceReactiveComposite [P3DashSeq]              ← 优先级 4：冲刺
│   ├── CondPlayerInRange (range=500)
│   ├── InverterDecorator
│   │   └── CondPlayerInRange (range=300)
│   ├── CondCooldownReady (key="cd_dash", cd=10)
│   ├── CondScytheInHand
│   └── ActDashAttack
│
├── SequenceReactiveComposite [P3ComboSeq]             ← 优先级 5：三连斩
│   ├── CondPlayerInRange (range=200)
│   ├── CondPlayerAboveBoss
│   ├── CondCooldownReady (key="cd_combo", cd=1)
│   ├── CondScytheInHand
│   └── ActComboSlash
│
├── SequenceReactiveComposite [P3KickSeq]              ← 优先级 6：踢人
│   ├── CondPlayerInRange (range=100)
│   ├── CondPlayerOnGround
│   ├── CondCooldownReady (key="cd_kick", cd=1)
│   ├── CondScytheInHand
│   └── ActKick
│
├── SequenceReactiveComposite [P3ThrowScytheSeq]       ← 优先级 7：扔镰刀
│   ├── CondAllP3SkillsOnCooldownOrBlocked
│   ├── CondScytheInHand
│   └── ActThrowScythe
│
└── SelectorComposite [P3FallbackSelector]              ← 兜底
    ├── SequenceReactiveComposite [P3MoveIfScythe]
    │   ├── CondScytheInHand
    │   └── ActP3MoveTowardPlayer
    └── ActP3IdleNoScythe                               ← 镰刀不在手 → 原地待机
```

---

## 15. Phase 3 新增 ConditionLeaf

### CondPlayerImprisoned

```gdscript
class_name CondPlayerImprisoned extends ConditionLeaf

func tick(actor: Node, _bb: Blackboard) -> int:
    var boss := actor as BossGhostWitch
    if boss == null: return FAILURE
    return SUCCESS if boss._player_imprisoned else FAILURE
```

### CondPlayerOnGround

```gdscript
class_name CondPlayerOnGround extends ConditionLeaf

@export var y_threshold: float = 50.0

func tick(actor: Node, _bb: Blackboard) -> int:
    var boss := actor as BossGhostWitch
    if boss == null: return FAILURE
    var player: Node2D = boss.get_priority_attack_target()
    if player == null: return FAILURE
    if player is CharacterBody2D:
        var p := player as CharacterBody2D
        if p.is_on_floor():
            var y_diff := abs(p.global_position.y - actor.global_position.y)
            if y_diff <= y_threshold:
                return SUCCESS
    return FAILURE
```

### CondPlayerOnPlatform

```gdscript
class_name CondPlayerOnPlatform extends ConditionLeaf

@export var y_threshold: float = 50.0

func tick(actor: Node, _bb: Blackboard) -> int:
    var boss := actor as BossGhostWitch
    if boss == null: return FAILURE
    var player: Node2D = boss.get_priority_attack_target()
    if player == null: return FAILURE
    if player is CharacterBody2D:
        var p := player as CharacterBody2D
        if p.is_on_floor():
            var y_diff := actor.global_position.y - p.global_position.y
            if y_diff > y_threshold:
                return SUCCESS
    return FAILURE
```

### CondPlayerAboveBoss

```gdscript
class_name CondPlayerAboveBoss extends ConditionLeaf

@export var y_threshold: float = 30.0

func tick(actor: Node, _bb: Blackboard) -> int:
    var boss := actor as BossGhostWitch
    if boss == null: return FAILURE
    var player: Node2D = boss.get_priority_attack_target()
    if player == null: return FAILURE
    var y_diff := actor.global_position.y - player.global_position.y
    return SUCCESS if y_diff > y_threshold else FAILURE
```

### CondScytheInHand

```gdscript
class_name CondScytheInHand extends ConditionLeaf

func tick(actor: Node, _bb: Blackboard) -> int:
    var boss := actor as BossGhostWitch
    if boss == null: return FAILURE
    return SUCCESS if boss._scythe_in_hand else FAILURE
```

### CondAllP3SkillsOnCooldownOrBlocked

```gdscript
class_name CondAllP3SkillsOnCooldownOrBlocked extends ConditionLeaf

func tick(actor: Node, blackboard: Blackboard) -> int:
    var actor_id := str(actor.get_instance_id())
    var now_ms: float = Time.get_ticks_msec()
    var keys := ["cd_imprison", "cd_summon", "cd_dash", "cd_combo", "cd_kick"]
    for key in keys:
        var end_time: float = blackboard.get_value(key, 0.0, actor_id)
        if now_ms >= end_time:
            return FAILURE
    return SUCCESS
```

---

## 16. Phase 3 ActionLeaf 详细设计

### 18.1 ActDashAttack（冲刺 — 冷却10s）

```gdscript
## 蓄力 → 快速冲刺 → 刹车减速 → 结束
class_name ActDashAttack extends ActionLeaf

enum Step { FACE_TARGET, CHARGE, DASH, BRAKE, DONE }
var _step: int = Step.FACE_TARGET
var _charge_end: float = 0.0
var _dash_dir: float = 1.0
var _dash_start_x: float = 0.0
var _dash_distance: float = 600.0
var _hit_player: bool = false

func before_run(actor: Node, _bb: Blackboard) -> void:
    _step = Step.FACE_TARGET
    _hit_player = false

func tick(actor: Node, blackboard: Blackboard) -> int:
    var boss := actor as BossGhostWitch
    if boss == null: return FAILURE

    match _step:
        Step.FACE_TARGET:
            var player := boss.get_priority_attack_target()
            if player == null: return FAILURE
            boss.face_toward(player)
            _dash_dir = signf(player.global_position.x - actor.global_position.x)
            if _dash_dir == 0.0: _dash_dir = 1.0
            _step = Step.CHARGE
            _charge_end = Time.get_ticks_msec() + boss.p3_dash_charge_time * 1000.0
            boss.anim_play(&"phase3/dash_charge", false)
            return RUNNING

        Step.CHARGE:
            if Time.get_ticks_msec() >= _charge_end:
                _dash_start_x = actor.global_position.x
                _step = Step.DASH
                boss.anim_play(&"phase3/dash", true)
            return RUNNING

        Step.DASH:
            actor.velocity.x = _dash_dir * boss.p3_dash_speed
            actor.velocity.y = 0.0
            if not _hit_player:
                for body in boss._scythe_detect_area.get_overlapping_bodies():
                    if body.is_in_group("player") and body.has_method("apply_damage"):
                        body.call("apply_damage", 1, actor.global_position)
                        _hit_player = true
                        break
            var traveled := abs(actor.global_position.x - _dash_start_x)
            if traveled >= _dash_distance or actor.is_on_wall():
                actor.velocity.x = 0.0
                _step = Step.BRAKE
                boss.anim_play(&"phase3/dash_brake", false)
            return RUNNING

        Step.BRAKE:
            actor.velocity.x = 0.0
            if boss.anim_is_finished(&"phase3/dash_brake"):
                _set_cooldown(actor, blackboard, "cd_dash", boss.p3_dash_cooldown)
                return SUCCESS
            return RUNNING
    return FAILURE

func _set_cooldown(actor: Node, bb: Blackboard, key: String, cd: float) -> void:
    bb.set_value(key, Time.get_ticks_msec() + cd * 1000.0, str(actor.get_instance_id()))

func interrupt(actor: Node, blackboard: Blackboard) -> void:
    actor.velocity.x = 0.0
    _step = Step.FACE_TARGET
    super(actor, blackboard)
```

### 18.2 ActKick（近身踢人 — 冷却1s）

```gdscript
## 踢人，判定绑定 leg 骨骼。踢中弹飞 300px + HP-1
class_name ActKick extends ActionLeaf

enum Step { PLAY, WAIT, DONE }
var _step: int = Step.PLAY

func before_run(actor: Node, _bb: Blackboard) -> void:
    _step = Step.PLAY

func tick(actor: Node, blackboard: Blackboard) -> int:
    var boss := actor as BossGhostWitch
    if boss == null: return FAILURE

    match _step:
        Step.PLAY:
            var player := boss.get_priority_attack_target()
            if player: boss.face_toward(player)
            boss.anim_play(&"phase3/kick", false)
            _step = Step.WAIT
            return RUNNING
        Step.WAIT:
            if boss.anim_is_finished(&"phase3/kick"):
                _set_cooldown(actor, blackboard, "cd_kick", boss.p3_kick_cooldown)
                return SUCCESS
            return RUNNING
    return FAILURE

func _set_cooldown(actor: Node, bb: Blackboard, key: String, cd: float) -> void:
    bb.set_value(key, Time.get_ticks_msec() + cd * 1000.0, str(actor.get_instance_id()))

func interrupt(actor: Node, blackboard: Blackboard) -> void:
    _step = Step.PLAY
    super(actor, blackboard)
```

### 18.3 ActComboSlash（三连斩 — 冷却1s）

```gdscript
## 3秒内连续检测 attack1/attack2/attack3 区域
class_name ActComboSlash extends ActionLeaf

enum Step { COMBO1, WAIT1, COMBO2, WAIT2, COMBO3, WAIT3, DONE }
var _step: int = Step.COMBO1

func before_run(actor: Node, _bb: Blackboard) -> void:
    _step = Step.COMBO1

func tick(actor: Node, blackboard: Blackboard) -> int:
    var boss := actor as BossGhostWitch
    if boss == null: return FAILURE

    match _step:
        Step.COMBO1:
            var player := boss.get_priority_attack_target()
            if player: boss.face_toward(player)
            boss.anim_play(&"phase3/combo1", false)
            _step = Step.WAIT1
            return RUNNING
        Step.WAIT1:
            if boss.anim_is_finished(&"phase3/combo1"):
                _step = Step.COMBO2
            return RUNNING
        Step.COMBO2:
            boss.anim_play(&"phase3/combo2", false)
            _step = Step.WAIT2
            return RUNNING
        Step.WAIT2:
            if boss.anim_is_finished(&"phase3/combo2"):
                _step = Step.COMBO3
            return RUNNING
        Step.COMBO3:
            boss.anim_play(&"phase3/combo3", false)
            _step = Step.WAIT3
            return RUNNING
        Step.WAIT3:
            if boss.anim_is_finished(&"phase3/combo3"):
                _set_cooldown(actor, blackboard, "cd_combo", boss.p3_combo_cooldown)
                return SUCCESS
            return RUNNING
    return FAILURE

func _set_cooldown(actor: Node, bb: Blackboard, key: String, cd: float) -> void:
    bb.set_value(key, Time.get_ticks_msec() + cd * 1000.0, str(actor.get_instance_id()))

func interrupt(actor: Node, blackboard: Blackboard) -> void:
    _step = Step.COMBO1
    var boss := actor as BossGhostWitch
    if boss: boss._close_all_combo_hitboxes()
    super(actor, blackboard)
```

### 18.4 ActThrowScythe（扔镰刀 — 兜底技能）

```gdscript
## 扔出镰刀 → 本体站桩等待 → 被打则镰刀回航 → 接住 → 结束
class_name ActThrowScythe extends ActionLeaf

enum Step { THROW_ANIM, SCYTHE_OUT, RECALL_WAIT, CATCH, DONE }
var _step: int = Step.THROW_ANIM

func before_run(actor: Node, _bb: Blackboard) -> void:
    _step = Step.THROW_ANIM

func tick(actor: Node, blackboard: Blackboard) -> int:
    var boss := actor as BossGhostWitch
    if boss == null: return FAILURE

    match _step:
        Step.THROW_ANIM:
            var player := boss.get_priority_attack_target()
            if player: boss.face_toward(player)
            boss.anim_play(&"phase3/throw_scythe", false)
            _step = Step.SCYTHE_OUT
            return RUNNING

        Step.SCYTHE_OUT:
            if boss._scythe_instance == null and boss.anim_is_finished(&"phase3/throw_scythe"):
                _spawn_scythe(boss)
            elif boss._scythe_instance == null:
                return RUNNING

            # 镰刀在外，本体原地待机
            boss.anim_play(&"phase3/idle_no_scythe", true)
            boss.velocity.x = 0.0

            if boss._scythe_recall_requested:
                boss._scythe_recall_requested = false
                _recall_scythe(boss)
                _step = Step.RECALL_WAIT
            elif boss._scythe_instance == null or not is_instance_valid(boss._scythe_instance):
                boss._scythe_in_hand = true
                boss.anim_play(&"phase3/catch_scythe", false)
                _step = Step.CATCH
            return RUNNING

        Step.RECALL_WAIT:
            boss.anim_play(&"phase3/idle_no_scythe", true)
            boss.velocity.x = 0.0
            if boss._scythe_instance == null or not is_instance_valid(boss._scythe_instance):
                boss._scythe_in_hand = true
                boss.anim_play(&"phase3/catch_scythe", false)
                _step = Step.CATCH
            return RUNNING

        Step.CATCH:
            if boss.anim_is_finished(&"phase3/catch_scythe"):
                return SUCCESS
            return RUNNING
    return FAILURE

func _spawn_scythe(boss: BossGhostWitch) -> void:
    var scythe: Node2D = boss._witch_scythe_scene.instantiate()
    scythe.add_to_group("witch_scythe")
    var player := boss.get_priority_attack_target()
    if scythe.has_method("setup"):
        scythe.call("setup", player, boss,
            boss.p3_scythe_track_interval,
            boss.p3_scythe_track_count,
            boss.p3_scythe_fly_speed,
            boss.p3_scythe_return_speed)
    scythe.global_position = boss.global_position
    boss.get_parent().add_child(scythe)
    boss._scythe_instance = scythe
    boss._scythe_in_hand = false

func _recall_scythe(boss: BossGhostWitch) -> void:
    if boss._scythe_instance != null and is_instance_valid(boss._scythe_instance):
        if boss._scythe_instance.has_method("recall"):
            boss._scythe_instance.call("recall", boss.global_position)

func interrupt(actor: Node, blackboard: Blackboard) -> void:
    _step = Step.THROW_ANIM
    super(actor, blackboard)
```

### 18.5 ActCastImprison（禁锢 — 地狱之手）

```gdscript
## 在玩家位置召唤地狱之手 → 0.5s 逃跑窗口 → 未逃则僵直3秒
class_name ActCastImprison extends ActionLeaf

enum Step { CAST_ANIM, WAIT_CAST, MONITOR, DONE }
var _step: int = Step.CAST_ANIM

func before_run(actor: Node, _bb: Blackboard) -> void:
    _step = Step.CAST_ANIM

func tick(actor: Node, blackboard: Blackboard) -> int:
    var boss := actor as BossGhostWitch
    if boss == null: return FAILURE

    match _step:
        Step.CAST_ANIM:
            boss.anim_play(&"phase3/imprison", false)
            _step = Step.WAIT_CAST
            return RUNNING
        Step.WAIT_CAST:
            if boss.anim_is_finished(&"phase3/imprison"):
                _spawn_hell_hand(boss)
                _step = Step.MONITOR
            return RUNNING
        Step.MONITOR:
            if boss._hell_hand_instance == null or not is_instance_valid(boss._hell_hand_instance):
                _set_cooldown(actor, blackboard, "cd_imprison", boss.p3_imprison_cooldown)
                return SUCCESS
            return RUNNING
    return FAILURE

func _spawn_hell_hand(boss: BossGhostWitch) -> void:
    var player := boss.get_priority_attack_target()
    if player == null: return
    var hand: Node2D = boss._hell_hand_scene.instantiate()
    hand.add_to_group("hell_hand")
    if hand.has_method("setup"):
        hand.call("setup", player, boss, boss.p3_imprison_escape_time, boss.p3_imprison_stun_time)
    hand.global_position = player.global_position
    boss.get_parent().add_child(hand)
    boss._hell_hand_instance = hand

func _set_cooldown(actor: Node, bb: Blackboard, key: String, cd: float) -> void:
    bb.set_value(key, Time.get_ticks_msec() + cd * 1000.0, str(actor.get_instance_id()))

func interrupt(actor: Node, blackboard: Blackboard) -> void:
    _step = Step.CAST_ANIM
    super(actor, blackboard)
```

### 18.6 ActRunSlash（奔跑斩击 — 禁锢反应）

```gdscript
## 检测到玩家被禁锢 → 跑到玩家位置 → 穿过 200px → 经过时斩击
class_name ActRunSlash extends ActionLeaf

enum Step { RUN_TO, SLASH_THROUGH, DONE }
var _step: int = Step.RUN_TO
var _target_x: float = 0.0
var _overshoot_x: float = 0.0
var _run_dir: float = 1.0
var _slashed: bool = false

func before_run(actor: Node, _bb: Blackboard) -> void:
    _step = Step.RUN_TO
    _slashed = false

func tick(actor: Node, _bb: Blackboard) -> int:
    var boss := actor as BossGhostWitch
    if boss == null: return FAILURE

    match _step:
        Step.RUN_TO:
            var player := boss.get_priority_attack_target()
            if player == null: return FAILURE
            _target_x = player.global_position.x
            _run_dir = signf(_target_x - actor.global_position.x)
            if _run_dir == 0.0: _run_dir = 1.0
            _overshoot_x = _target_x + _run_dir * boss.p3_run_slash_overshoot_px
            boss.face_toward(player)
            boss.anim_play(&"phase3/run_slash", true)
            _step = Step.SLASH_THROUGH
            return RUNNING

        Step.SLASH_THROUGH:
            actor.velocity.x = _run_dir * boss.p3_run_speed
            if not _slashed:
                var player := boss.get_priority_attack_target()
                if player != null:
                    var passed := (_run_dir > 0 and actor.global_position.x >= _target_x) \
                                or (_run_dir < 0 and actor.global_position.x <= _target_x)
                    if passed:
                        if player.has_method("apply_damage"):
                            player.call("apply_damage", 1, actor.global_position)
                        _slashed = true
                        boss._player_imprisoned = false
                        if boss._hell_hand_instance and is_instance_valid(boss._hell_hand_instance):
                            boss._hell_hand_instance.queue_free()
            var reached := (_run_dir > 0 and actor.global_position.x >= _overshoot_x) \
                          or (_run_dir < 0 and actor.global_position.x <= _overshoot_x)
            if reached or actor.is_on_wall():
                actor.velocity.x = 0.0
                boss.anim_play(&"phase3/idle", true)
                return SUCCESS
            return RUNNING
    return FAILURE

func interrupt(actor: Node, blackboard: Blackboard) -> void:
    actor.velocity.x = 0.0
    _step = Step.RUN_TO
    super(actor, blackboard)
```

### 18.7 ActThrowScytheUpward（向上扔追踪镰刀 — 禁锢反应：玩家在上方）

```gdscript
## 跑到玩家 X 位置 → 向上扔镰刀 → 1秒内追踪到玩家位置
class_name ActThrowScytheUpward extends ActionLeaf

enum Step { RUN_TO_X, THROW_UP, WAIT_SCYTHE, DONE }
var _step: int = Step.RUN_TO_X

func before_run(actor: Node, _bb: Blackboard) -> void:
    _step = Step.RUN_TO_X

func tick(actor: Node, _bb: Blackboard) -> int:
    var boss := actor as BossGhostWitch
    if boss == null: return FAILURE

    match _step:
        Step.RUN_TO_X:
            var player := boss.get_priority_attack_target()
            if player == null: return FAILURE
            var h_dist := abs(actor.global_position.x - player.global_position.x)
            if h_dist < 30.0:
                actor.velocity.x = 0.0
                _step = Step.THROW_UP
            else:
                var dir := signf(player.global_position.x - actor.global_position.x)
                actor.velocity.x = dir * boss.p3_run_speed
                boss.anim_play(&"phase3/walk", true)
            return RUNNING

        Step.THROW_UP:
            actor.velocity.x = 0.0
            boss.anim_play(&"phase3/throw_scythe", false)
            if boss.anim_is_finished(&"phase3/throw_scythe"):
                _spawn_tracking_scythe(boss)
                _step = Step.WAIT_SCYTHE
            return RUNNING

        Step.WAIT_SCYTHE:
            boss.anim_play(&"phase3/idle_no_scythe", true)
            if boss._scythe_instance == null or not is_instance_valid(boss._scythe_instance):
                boss._scythe_in_hand = true
                boss.anim_play(&"phase3/catch_scythe", false)
                boss._player_imprisoned = false
                if boss._hell_hand_instance and is_instance_valid(boss._hell_hand_instance):
                    boss._hell_hand_instance.queue_free()
                return SUCCESS
            return RUNNING
    return FAILURE

func _spawn_tracking_scythe(boss: BossGhostWitch) -> void:
    var scythe: Node2D = boss._witch_scythe_scene.instantiate()
    scythe.add_to_group("witch_scythe")
    var player := boss.get_priority_attack_target()
    if scythe.has_method("setup_tracking"):
        scythe.call("setup_tracking", player, boss, boss.p3_scythe_fly_speed)
    scythe.global_position = boss.global_position + Vector2(0, -50)
    boss.get_parent().add_child(scythe)
    boss._scythe_instance = scythe
    boss._scythe_in_hand = false

func interrupt(actor: Node, blackboard: Blackboard) -> void:
    actor.velocity.x = 0.0
    _step = Step.RUN_TO_X
    super(actor, blackboard)
```

### 18.8 ActSummonGhosts（召唤幽灵 — 施法含 combo3 攻击）

```gdscript
## 施法起手（含 combo3 攻击判定）→ 生成幽灵波次 → summon_loop 维持 → 等所有 GhostSummon 销毁 → 结束
## 全程不可移动
class_name ActSummonGhosts extends ActionLeaf

enum Step { CAST, SUMMON_LOOP, DONE }
var _step: int = Step.CAST
var _wave_index: int = 0
var _wave_timer: float = 0.0
var _wave_interval: float = 0.0
var _cast_done: bool = false

func before_run(actor: Node, _bb: Blackboard) -> void:
    _step = Step.CAST
    _wave_index = 0
    _wave_timer = 0.0
    _cast_done = false

func tick(actor: Node, blackboard: Blackboard) -> int:
    var boss := actor as BossGhostWitch
    if boss == null: return FAILURE
    var dt := get_physics_process_delta_time()
    actor.velocity.x = 0.0  # 全程锁定移动

    match _step:
        Step.CAST:
            if not _cast_done:
                boss.anim_play(&"phase3/summon", false)
                _wave_interval = 5.0 / float(boss.p3_summon_wave_count)

            _wave_timer += dt
            var expected_waves := int(_wave_timer / _wave_interval)
            if expected_waves > _wave_index and _wave_index < boss.p3_summon_wave_count:
                _spawn_wave(boss)
                _wave_index += 1

            if boss.anim_is_finished(&"phase3/summon"):
                _cast_done = true
                _step = Step.SUMMON_LOOP
            return RUNNING

        Step.SUMMON_LOOP:
            boss.anim_play(&"phase3/summon_loop", true)
            if _wave_index < boss.p3_summon_wave_count:
                _wave_timer += dt
                var expected_waves := int(_wave_timer / _wave_interval)
                if expected_waves > _wave_index:
                    _spawn_wave(boss)
                    _wave_index += 1

            var remaining: Array[Node] = actor.get_tree().get_nodes_in_group("ghost_summon")
            if remaining.is_empty() and _wave_index >= boss.p3_summon_wave_count:
                boss.anim_play(&"phase3/idle", true)
                _set_cooldown(actor, blackboard, "cd_summon", boss.p3_summon_cooldown)
                return SUCCESS
            return RUNNING
    return FAILURE

func _spawn_wave(boss: BossGhostWitch) -> void:
    var player := boss.get_priority_attack_target()
    if player == null: return
    var positions: Array[Vector2] = []
    positions.append(player.global_position)
    for i in range(boss.p3_summon_circle_count - 1):
        var random_x := player.global_position.x + randf_range(-300, 300)
        positions.append(Vector2(random_x, player.global_position.y))
    for pos in positions:
        var summon: Node2D = boss._ghost_summon_scene.instantiate()
        summon.add_to_group("ghost_summon")
        if summon.has_method("setup"):
            summon.call("setup", 0.3)
        summon.global_position = pos
        boss.get_parent().add_child(summon)

func _set_cooldown(actor: Node, bb: Blackboard, key: String, cd: float) -> void:
    bb.set_value(key, Time.get_ticks_msec() + cd * 1000.0, str(actor.get_instance_id()))

func interrupt(actor: Node, blackboard: Blackboard) -> void:
    _step = Step.CAST
    _cast_done = false
    var boss := actor as BossGhostWitch
    if boss: boss._close_all_combo_hitboxes()
    super(actor, blackboard)
```

### 18.9 ActP3MoveTowardPlayer（Phase 3 移动）

```gdscript
class_name ActP3MoveTowardPlayer extends ActionLeaf

func tick(actor: Node, _bb: Blackboard) -> int:
    var boss := actor as BossGhostWitch
    if boss == null: return FAILURE
    if not boss._scythe_in_hand:
        actor.velocity.x = 0.0
        boss.anim_play(&"phase3/idle_no_scythe", true)
        return RUNNING
    var player := boss.get_priority_attack_target()
    if player == null:
        actor.velocity.x = 0.0
        boss.anim_play(&"phase3/idle", true)
        return RUNNING
    var h_dist := abs(player.global_position.x - actor.global_position.x)
    if h_dist < 30.0:
        actor.velocity.x = 0.0
        boss.anim_play(&"phase3/idle", true)
    else:
        var dir := signf(player.global_position.x - actor.global_position.x)
        actor.velocity.x = dir * boss.p3_move_speed
        boss.face_toward(player)
        boss.anim_play(&"phase3/walk", true)
    return RUNNING
```

### 18.10 ActP3IdleNoScythe（无镰刀待机兜底）

```gdscript
## 镰刀不在手时的兜底：原地待机，等待镰刀回航
class_name ActP3IdleNoScythe extends ActionLeaf

func tick(actor: Node, _bb: Blackboard) -> int:
    var boss := actor as BossGhostWitch
    if boss == null: return FAILURE
    actor.velocity.x = 0.0
    boss.anim_play(&"phase3/idle_no_scythe", true)
    return RUNNING
```

---

## 17. Phase 3 子实例场景设计

### 17.1 WitchScythe.tscn（镰刀实例）

**节点结构：**
```
WitchScythe (Node2D)  # witch_scythe.gd
├── SpineSprite        # 镰刀飞行动画
└── HitArea (Area2D)   # 全程碰到玩家即伤害
    └── CollisionShape2D  # 默认 enabled（扔出即生效）
```

> 不需要 AttackArea（没有砍击动作）。HitArea 全程开启，碰到就伤害。

**动画清单：**

| 动画名 | loop | 用途 |
|---|---|---|
| `fly` | true | 镰刀飞行旋转（扔出后全程播放）|
| `return_end` | false | 回航到达 Boss 身边后的结束过渡 |

**witch_scythe.gd 核心逻辑：**

```gdscript
extends Node2D

## 镰刀实例：fly 动画循环飞行，每次检测玩家位置并转向飞过去，
## 检测次数用完后直线回航，到达后播 return_end，播完通知 Boss。
## 全程碰到玩家就伤害。

enum ScytheState { FLYING, RETURNING, RETURN_END }

var _state: int = ScytheState.FLYING
var _player: Node2D = null
var _boss: Node2D = null
var _track_interval: float = 1.0
var _track_count_max: int = 3
var _track_count: int = 0
var _fly_speed: float = 300.0
var _return_speed: float = 500.0
var _target_pos: Vector2 = Vector2.ZERO
var _track_timer: float = 0.0
var _hit_player_this_frame: bool = false

func setup(player: Node2D, boss: Node2D, track_interval: float,
           track_count: int, fly_speed: float, return_speed: float) -> void:
    _player = player
    _boss = boss
    _track_interval = track_interval
    _track_count_max = track_count
    _fly_speed = fly_speed
    _return_speed = return_speed
    _track_count = 0
    _track_timer = 0.0
    _state = ScytheState.FLYING
    _update_target()

func setup_tracking(player: Node2D, boss: Node2D, fly_speed: float) -> void:
    _player = player
    _boss = boss
    _track_interval = 0.0
    _track_count_max = 1
    _fly_speed = fly_speed
    _return_speed = fly_speed * 1.5
    _track_count = 0
    _state = ScytheState.FLYING
    _update_target()

func _ready() -> void:
    _play_anim(&"fly", true)
    $HitArea.body_entered.connect(_on_body_entered)

func _physics_process(dt: float) -> void:
    _hit_player_this_frame = false
    match _state:
        ScytheState.FLYING: _tick_flying(dt)
        ScytheState.RETURNING: _tick_returning(dt)
        ScytheState.RETURN_END: _tick_return_end()

func _tick_flying(dt: float) -> void:
    var dir := (_target_pos - global_position).normalized()
    global_position += dir * _fly_speed * dt
    if global_position.distance_to(_target_pos) < 20.0:
        _track_count += 1
        if _track_count >= _track_count_max:
            _state = ScytheState.RETURNING
        else:
            _track_timer = 0.0
            _update_target()
    _track_timer += dt
    if _track_timer >= _track_interval and _track_count < _track_count_max:
        _track_timer = 0.0
        _update_target()

func _tick_returning(dt: float) -> void:
    if _boss == null or not is_instance_valid(_boss):
        queue_free()
        return
    var boss_pos := _boss.global_position
    var dir := (boss_pos - global_position).normalized()
    global_position += dir * _return_speed * dt
    if global_position.distance_to(boss_pos) < 30.0:
        _play_anim(&"return_end", false)
        _state = ScytheState.RETURN_END

func _tick_return_end() -> void:
    if _is_anim_finished(&"return_end"):
        if _boss and is_instance_valid(_boss):
            _boss._scythe_in_hand = true
            _boss._scythe_instance = null
        queue_free()

func recall(_target_pos: Vector2) -> void:
    _state = ScytheState.RETURNING

func _update_target() -> void:
    if _player and is_instance_valid(_player):
        _target_pos = _player.global_position

func _on_body_entered(body: Node2D) -> void:
    if _hit_player_this_frame: return
    if body.is_in_group("player") and body.has_method("apply_damage"):
        body.call("apply_damage", 1, global_position)
        _hit_player_this_frame = true

func _play_anim(_name: StringName, _loop: bool) -> void:
    pass  # 实际走 AnimDriverSpine
func _is_anim_finished(_name: StringName) -> bool:
    return false
```

### 17.2 HellHand.tscn（地狱之手）

**节点结构：**
```
HellHand (Node2D)  # hell_hand.gd
├── SpineSprite     # 地狱之手 Spine 动画
├── CaptureArea (Area2D)  # 捕捉检测区（绑定 Spine 骨骼）
│   └── CollisionShape2D
└── HitArea (Area2D)       # 被 ghostfist 打碎
    └── CollisionShape2D
```

**动画清单：**

| 动画名 | loop | 事件 | 用途 |
|---|---|---|---|
| `appear` | false | `capture_check`（检测帧） | 地狱之手从地面出现 |
| `hold` | true | — | 抓住玩家，持续禁锢 |
| `close` | false | — | 没抓到 或 被打断 或 禁锢结束后的收回消失 |

**事件驱动逻辑：不用 timer，用 Spine 事件 `capture_check` 决定是否抓住玩家。**

**hell_hand.gd 核心逻辑：**

```gdscript
extends Node2D

enum HandState { APPEAR, HOLD, CLOSING }

var _state: int = HandState.APPEAR
var _player: Node2D = null
var _boss: Node2D = null
var _stun_time: float = 3.0
var _imprison_end: float = 0.0
var _player_captured: bool = false

func setup(player: Node2D, boss: Node2D, escape_time: float, stun_time: float) -> void:
    _player = player
    _boss = boss
    _stun_time = stun_time
    # escape_time 不再用 timer，由动画事件 capture_check 的时机决定

func _ready() -> void:
    _state = HandState.APPEAR
    _play_anim(&"appear", false)

    # 连接 Spine 事件
    var spine: Node = get_node_or_null("SpineSprite")
    if spine and spine.has_signal("animation_event"):
        spine.animation_event.connect(_on_spine_event)

    # ghostfist 击碎检测
    $HitArea.area_entered.connect(_on_ghostfist_hit)

func _on_spine_event(a1, a2, a3, a4) -> void:
    var event_name := _extract_event_name(a1, a2, a3, a4)
    match event_name:
        &"capture_check":
            # 动画中的检测帧：玩家还在 CaptureArea 内？
            if _is_player_in_capture_area():
                _capture_player()
            else:
                # 没抓到 → 播放收回动画消失
                _state = HandState.CLOSING
                _play_anim(&"close", false)

func _physics_process(_dt: float) -> void:
    match _state:
        HandState.APPEAR:
            # 等待 Spine 事件 capture_check 触发
            if _is_anim_finished(&"appear") and not _player_captured:
                # appear 动画播完但 capture_check 还没触发（防御性兜底）
                _state = HandState.CLOSING
                _play_anim(&"close", false)
        HandState.HOLD:
            if Time.get_ticks_msec() >= _imprison_end:
                _release_player()
                _state = HandState.CLOSING
                _play_anim(&"close", false)
        HandState.CLOSING:
            if _is_anim_finished(&"close"):
                _cleanup_and_free()

func _is_player_in_capture_area() -> bool:
    for body in $CaptureArea.get_overlapping_bodies():
        if body.is_in_group("player"): return true
    return false

func _capture_player() -> void:
    _player_captured = true
    _state = HandState.HOLD
    _imprison_end = Time.get_ticks_msec() + _stun_time * 1000.0
    _play_anim(&"hold", true)
    if _player and is_instance_valid(_player):
        if _player.has_method("set_external_control_frozen"):
            _player.call("set_external_control_frozen", true)
    if _boss and is_instance_valid(_boss):
        _boss._player_imprisoned = true

func _release_player() -> void:
    _player_captured = false
    if _player and is_instance_valid(_player):
        if _player.has_method("set_external_control_frozen"):
            _player.call("set_external_control_frozen", false)
    if _boss and is_instance_valid(_boss):
        _boss._player_imprisoned = false

func _on_ghostfist_hit(area: Area2D) -> void:
    if area.is_in_group("ghost_fist_hitbox"):
        _release_player()
        _state = HandState.CLOSING
        _play_anim(&"close", false)

func _cleanup_and_free() -> void:
    _release_player()
    queue_free()

func _exit_tree() -> void:
    _release_player()

func _extract_event_name(a1, a2, a3, a4) -> StringName:
    for a in [a1, a2, a3, a4]:
        if a is Object and a.has_method("get_data"):
            var data = a.get_data()
            if data != null and data.has_method("get_event_name"):
                return StringName(data.get_event_name())
    return &""

func _play_anim(_name: StringName, _loop: bool) -> void:
    pass  # 实际走 AnimDriverSpine
func _is_anim_finished(_name: StringName) -> bool:
    return false
```

### 17.3 GhostSummon.tscn（召唤幽灵 — 圆圈飞出）

**节点结构：**
```
GhostSummon (Node2D)  # ghost_summon.gd
├── SpineSprite       # 圆圈 + 飞出幽灵动画（ghost 骨骼）
└── GhostHitArea (Area2D)  # 伤害检测盒，绑定 ghost 骨骼
    └── CollisionShape2D    # 默认 disabled
```

> HitArea 绑定在 Spine 的 `ghost` 骨骼上，每帧跟随骨骼位置。
> 伤害检测由 Spine 事件控制开关，不是 timer。

**动画清单：**

| 动画名 | loop | 事件 | 用途 |
|---|---|---|---|
| `circle_appear` | false | — | 地面圆圈出现 |
| `ghost_fly_out` | false | `ghost_hitbox_on`、`ghost_hitbox_off` | 亡灵从圆圈中往上飞出 |

**ghost_summon.gd 核心逻辑：**

```gdscript
extends Node2D

var _delay: float = 0.3
var _spawned: bool = false
var _lifetime: float = 3.0
var _ghost_hit_area: Area2D = null

func setup(delay: float) -> void:
    _delay = delay

func _ready() -> void:
    _ghost_hit_area = $GhostHitArea
    _play_anim(&"circle_appear", false)
    _set_hitarea_enabled(false)

    # 连接 Spine 事件
    var spine: Node = get_node_or_null("SpineSprite")
    if spine and spine.has_signal("animation_event"):
        spine.animation_event.connect(_on_spine_event)

    # 碰撞伤害
    _ghost_hit_area.body_entered.connect(_on_body_entered)

func _physics_process(dt: float) -> void:
    if not _spawned:
        _delay -= dt
        if _delay <= 0.0:
            _spawned = true
            _play_anim(&"ghost_fly_out", false)
            # hitbox 由 Spine 事件 ghost_hitbox_on 控制，不在这里开
    else:
        _lifetime -= dt
        if _lifetime <= 0.0:
            queue_free()

    # 每帧同步 GhostHitArea 到 ghost 骨骼位置
    _sync_hitarea_to_bone()

func _on_spine_event(a1, a2, a3, a4) -> void:
    var event_name := _extract_event_name(a1, a2, a3, a4)
    match event_name:
        &"ghost_hitbox_on":
            _set_hitarea_enabled(true)
        &"ghost_hitbox_off":
            _set_hitarea_enabled(false)

func _sync_hitarea_to_bone() -> void:
    if _ghost_hit_area == null: return
    var spine: Node = get_node_or_null("SpineSprite")
    if spine == null: return
    # 通过 AnimDriverSpine 或直接 SpineSprite 获取骨骼位置
    if spine.has_method("get_skeleton"):
        var skeleton = spine.get_skeleton()
        if skeleton and skeleton.has_method("find_bone"):
            var bone = skeleton.find_bone("ghost")
            if bone:
                # 使用骨骼世界坐标
                var bone_pos := Vector2.ZERO
                if bone.has_method("get_world_position_x") and bone.has_method("get_world_position_y"):
                    bone_pos = Vector2(bone.get_world_position_x(), bone.get_world_position_y())
                    _ghost_hit_area.position = bone_pos

func _on_body_entered(body: Node2D) -> void:
    if body.is_in_group("player") and body.has_method("apply_damage"):
        body.call("apply_damage", 1, global_position)

func _set_hitarea_enabled(enabled: bool) -> void:
    _ghost_hit_area.set_deferred("monitoring", enabled)
    for child in _ghost_hit_area.get_children():
        if child is CollisionShape2D:
            child.set_deferred("disabled", not enabled)

func _extract_event_name(a1, a2, a3, a4) -> StringName:
    for a in [a1, a2, a3, a4]:
        if a is Object and a.has_method("get_data"):
            var data = a.get_data()
            if data != null and data.has_method("get_event_name"):
                return StringName(data.get_event_name())
    return &""

func _play_anim(_name: StringName, _loop: bool) -> void:
    pass  # 实际走 SpineSprite
```
---

## 18. Phase 3 死亡流程

```
hp <= 0 时：
1. hp_locked = true
2. 中断所有攻击流
3. 清理场景中所有 Boss 子实例：
   → call_group("witch_scythe", "queue_free")
   → call_group("hell_hand", "queue_free")
   → call_group("ghost_summon", "queue_free")
   → 以及 Phase 2 残留（ghost_bomb, ghost_wraith, ghost_elite, ghost_tug）
4. Boss 播放 phase3/death
5. Spine 事件 "death_finished" 后切到 phase3/death_loop
6. death_loop 持续播放
```

```gdscript
func _begin_death() -> void:
    hp_locked = true
    _phase_transitioning = true
    velocity = Vector2.ZERO
    _cleanup_all_instances()
    anim_play(&"phase3/death", false)

func _on_anim_completed(_track: int, anim_name: StringName) -> void:
    if anim_name == _current_anim:
        _current_anim_finished = true
    if anim_name == &"phase3/death":
        anim_play(&"phase3/death_loop", true)

func _cleanup_all_instances() -> void:
    for group_name in ["ghost_bomb", "ghost_wraith", "ghost_elite", "ghost_tug",
                       "witch_scythe", "hell_hand", "ghost_summon"]:
        get_tree().call_group(group_name, "queue_free")
```

---

## 19. 全阶段 Spine 动画事件清单

### 19.1 魔女石像 / 无头骑士（主 SpineSprite）

**Phase 1 动画：**

| 动画 | 事件名 | 触发时机 | 用途 |
|---|---|---|---|
| `phase1/idle` | — | — | 怀抱婴儿待机 |
| `phase1/idle_no_baby` | — | — | 婴儿投出后待机 |
| `phase1/walk` | — | — | 缓慢向玩家移动 |
| `phase1/start_attack` | `start_attack_hitbox_on` | 攻击帧 | 开启 ScytheDetectArea 伤害判定 |
| `phase1/start_attack` | `start_attack_hitbox_off` | 攻击结束 | 关闭伤害判定 |
| `phase1/start_attack_exter` | `battle_start` | 动画末尾 | 标记战斗开始 |
| `phase1/throw` | `baby_release` | 投掷帧 | 婴儿脱离 mark2D |
| `phase1/throw` | `throw_done` | 动画末尾 | 切到 idle_no_baby |
| `phase1/catch_baby` | `baby_return` | 抱住帧 | 婴儿重新绑定 |
| `phase1/hurt` | — | — | 受击闪白 |
| `phase1/phase1_to_phase2` | `stand_up` | 石像站起 | 切换碰撞体 |
| `phase1/phase1_to_phase2` | `phase2_ready` | 动画末尾 | 进入 Phase 2 |

**Phase 2 动画：**

| 动画 | 事件名 | 触发时机 | 用途 |
|---|---|---|---|
| `phase2/idle` | — | — | 祈祷形态待机 |
| `phase2/walk` | — | — | 向玩家移动 |
| `phase2/scythe_slash` | `scythe_hitbox_on` | 挥镰帧 | 开启伤害 |
| `phase2/scythe_slash` | `scythe_hitbox_off` | 挥镰结束 | 关闭伤害 |
| `phase2/ghost_tug_cast` | `tug_spawn` | 施法帧 | 生成拔河实例 |
| `phase2/tombstone_cast` | `tombstone_ready` | 动画末尾 | 施法完毕 |
| `phase2/tombstone_appear` | `appear_done` | 动画末尾 | 渐显完毕 |
| `phase2/tombstone_hover` | — | 循环 | 空中悬停 |
| `phase2/tombstone_throw` | `fall_start` | 投掷发力帧 | 准备下落 |
| `phase2/tombstone_fall` | — | 循环 | 高速下落 |
| `phase2/tombstone_land` | `ground_hitbox_on` | 撞地瞬间 | 开启落地伤害 |
| `phase2/tombstone_land` | `ground_hitbox_off` | 冲击结束 | 关闭伤害 |
| `phase2/undead_wind_cast` | `wind_start` | 施法帧 | 开始生成亡灵 |
| `phase2/undead_wind_cast` | `realhurtbox_off` | 施法开始 | 关闭 RealHurtbox |
| `phase2/undead_wind_end` | `realhurtbox_on` | 施法结束 | 恢复 RealHurtbox |
| `phase2/phase2_to_phase3` | `shatter` | 石像碎裂 | 视觉碎裂 |
| `phase2/phase2_to_phase3` | `phase3_ready` | 动画末尾 | 进入 Phase 3 |

**Phase 3 动画：**

| 动画 | 事件名 | loop | 用途 |
|---|---|---|---|
| `phase3/idle` | — | true | 站立待机 |
| `phase3/idle_no_scythe` | — | true | 无镰刀待机（扔出期间） |
| `phase3/walk` | `footstep` | true | 移动 |
| `phase3/dash_charge` | `charge_ready` | false | 冲刺蓄力 |
| `phase3/dash` | `dash_hitbox_on`、`dash_hitbox_off` | true | 冲刺中 |
| `phase3/dash_brake` | — | false | 冲刺刹车减速 |
| `phase3/kick` | `kick_hitbox_on`、`kick_hitbox_off` | false | 踢人 |
| `phase3/throw_scythe` | `scythe_release` | false | 扔镰刀 |
| `phase3/catch_scythe` | `scythe_catch` | false | 接回镰刀 |
| `phase3/imprison` | `hand_spawn` | false | 召唤地狱之手 |
| `phase3/run_slash` | `slash_hitbox_on`、`slash_hitbox_off` | true | 奔跑斩击 |
| `phase3/combo1` | `combo1_hitbox_on`、`combo1_hitbox_off` | false | 三连斩第1击 |
| `phase3/combo2` | `combo2_hitbox_on`、`combo2_hitbox_off` | false | 三连斩第2击 |
| `phase3/combo3` | `combo3_hitbox_on`、`combo3_hitbox_off` | false | 三连斩第3击 |
| `phase3/summon` | `combo3_hitbox_on`、`combo3_hitbox_off`、`circle_spawn` | false | 召唤起手（含combo3攻击） |
| `phase3/summon_loop` | — | true | 维持施法姿态 |
| `phase3/death` | `death_finished` | false | 死亡 |
| `phase3/death_loop` | — | true | 死亡循环 |

### 19.2 婴儿石像（BabyStatue/SpineSprite）

| 动画 | 事件名 | 触发时机 | 用途 |
|---|---|---|---|
| `baby/spin` | — | 循环 | 投掷飞行中旋转 |
| `baby/explode` | `explode_hitbox_on` | 爆炸帧 | 开启爆炸伤害 |
| `baby/explode` | `explode_hitbox_off` | 爆炸结束 | 关闭伤害 |
| `baby/explode` | `realhurtbox_on` | bodybox 关闭后 | 开启 BabyRealHurtbox |
| `baby/repair` | `realhurtbox_off` | 修复完毕 | 关闭 BabyRealHurtbox |
| `baby/repair` | `repair_done` | 动画末尾 | 触发攻击流1 |
| `baby/dash` | `dash_go` | 蓄力完毕帧 | 开始真正位移，切到 dash_loop |
| `baby/dash` | `dash_hitbox_on` | dash_go 同时或略后 | 开启 BabyAttackArea |
| `baby/dash_loop` | — | 循环 | 冲刺中循环（冲刺去和冲刺回都复用）|
| `baby/idle` | true | — | 冲刺到达后 0.7s 等待期间播放 |
| `baby/wind_up` | — | false | 收招动画 |
| `baby/return` | — | 循环 | 扇翅膀飞回母体 |
| `baby/phase1_to_phase2` | `become_halo` | 变形完成 | bodybox 消失，realhurtbox 永久开启 |

### 19.3 幽灵拔河（GhostTug/SpineSprite）

| 动画 | 事件名 | 触发时机 | 用途 |
|---|---|---|---|
| `appear` | — | 出场 | 从透明渐显出现（Spine 动画控制透明度）|
| `move_loop` | `move` | 每次拉拽帧 | 触发 `_pull_player_toward_boss()` |
| `hit` | — | 被 ghostfist 打中 | 受击反应 + 渐隐消失（Spine 动画控制透明度），播完后 `queue_free()` |

---

## 20. 全阶段攻击参数总表

### Phase 1

| 攻击名 | 触发条件 | 范围(px) | 冷却(s) | 伤害 | 可打断 | 优先级 |
|---|---|---|---|---|---|---|
| 开场一击 | 首次检测到玩家 | 近身检测区 | 一次性 | 1 | 否 | — |
| 投掷婴儿石像 | 玩家 ≤500px | 500 | 依赖返航 | 0 | 否 | 唯一主动 |
| 婴儿爆炸 | 撞地面/玩家 | 爆炸范围 | — | 1 | 否 | 自动 |
| 攻击流1-冲刺(去) | 修复完毕+玩家在检测区 | 冲刺路径 | — | 1(碰撞) | 否 | 自动 |
| 攻击流1-等待 | 冲刺到达 | — | 0.7s | 0 | — | 自动 |
| 攻击流1-冲刺(回) | 等待结束 | 冲回原位 | — | 1(碰撞) | 否 | 自动 |

### Phase 2

| 攻击名 | 触发条件 | 范围(px) | 冷却(s) | 伤害 | 可打断 | 优先级 |
|---|---|---|---|---|---|---|
| 镰刀斩 | ≤100px | 100 | 1 | 1 | 否 | 1 |
| 飞天砸落 | ≤500px | 500 | 3 | 1(落地) | 否 | 2 |
| 亡灵气流 | 100~300px | 300 | 15 | 1(碰撞) | ghostfist消灭 | 3 |
| 幽灵拔河 | >500px | 无限 | 5 | 0(拉拽) | ghostfist打断 | 4 |
| 自爆幽灵 | 空闲时每5s | 追踪 | 5 | 1(自爆) | ghostfist消灭 | 被动 |
| 向玩家移动 | 技能cd中/范围外 | — | — | 0 | — | 兜底 |

### Phase 3

| 攻击名 | 触发条件 | 范围(px) | 冷却(s) | 伤害 | 可打断 | 优先级 |
|---|---|---|---|---|---|---|
| 奔跑斩击 | 玩家被禁锢+在地面 | 穿过玩家 | — | 1 | 否 | 1 |
| 向上扔追踪镰刀 | 玩家被禁锢+在上方 | 追踪 | — | 1 | 否 | 1 |
| 禁锢(地狱之手) | 玩家在地面+镰刀在手 | 全场 | 10 | 0(禁锢) | ghostfist解 | 2 |
| 召唤幽灵 | 跳板上+≤500px+镰刀在手 | 500 | 8(待定) | 1+起手combo3 | 否，全程锁定 | 3 |
| 冲刺 | 300~500px+镰刀在手 | 500 | 10 | 1(碰撞) | 否 | 4 |
| 三连斩 | ≤200px+玩家在上方+镰刀在手 | 200 | 1 | 1/hit | 否 | 5 |
| 踢人 | ≤100px+玩家在地面+镰刀在手 | 100 | 1 | 1+弹飞300px | 否 | 6 |
| 扔镰刀 | 其他全不可用+镰刀在手 | 无限 | — | 1(砍击) | 被打→回航 | 7 |

---

## 21. 文件目录规划

```
scene/enemies/boss_ghost_witch/
├── BossGhostWitch.tscn           # Boss 主场景
├── boss_ghost_witch.gd           # Boss 主脚本
├── GhostTug.tscn                 # 幽灵拔河实例
├── ghost_tug.gd
├── GhostBomb.tscn                # 自爆幽灵实例
├── ghost_bomb.gd
├── GhostWraith.tscn              # 亡灵气流（3型合一）
├── ghost_wraith.gd
├── GhostElite.tscn               # 精英亡灵
├── ghost_elite.gd
├── WitchScythe.tscn              # Phase 3 镰刀实例
├── witch_scythe.gd
├── HellHand.tscn                 # Phase 3 地狱之手
├── hell_hand.gd
├── GhostSummon.tscn              # Phase 3 召唤幽灵
├── ghost_summon.gd
├── conditions/
│   ├── cond_is_phase.gd
│   ├── cond_phase_transitioning.gd
│   ├── cond_player_in_range.gd
│   ├── cond_cooldown_ready.gd
│   ├── cond_baby_in_hug.gd
│   ├── cond_battle_not_started.gd
│   ├── cond_all_skills_on_cooldown.gd
│   ├── cond_ghost_bomb_can_spawn.gd
│   ├── cond_player_imprisoned.gd
│   ├── cond_player_on_ground.gd
│   ├── cond_player_on_platform.gd
│   ├── cond_player_above_boss.gd
│   ├── cond_scythe_in_hand.gd
│   └── cond_all_p3_skills_blocked.gd
└── actions/
    ├── act_start_battle.gd
    ├── act_throw_baby.gd
    ├── act_baby_attack_flow.gd
    ├── act_slow_move_to_player.gd
    ├── act_scythe_slash.gd
    ├── act_tombstone_drop.gd
    ├── act_undead_wind.gd
    ├── act_ghost_tug.gd
    ├── act_spawn_ghost_bomb.gd
    ├── act_move_toward_player.gd
    ├── act_wait_transition.gd
    ├── act_dash_attack.gd
    ├── act_kick.gd
    ├── act_combo_slash.gd
    ├── act_throw_scythe.gd
    ├── act_cast_imprison.gd
    ├── act_run_slash.gd
    ├── act_throw_scythe_upward.gd
    ├── act_summon_ghosts.gd
    ├── act_p3_move_toward_player.gd
    └── act_p3_idle_no_scythe.gd
```

---

## 22. 实施顺序建议

1. **创建 Boss 主场景 + 主脚本骨架**：节点结构、HP 系统、碰撞配置、override apply_hit/on_chain_hit。
2. **Phase 1 行为树 + 婴儿石像**：开场动画→投掷→爆炸→修复→攻击流1→返航。
3. **Phase 1→2 过渡动画**：变身流程。
4. **Phase 2 行为树**：镰刀斩→飞天砸落→亡灵气流→幽灵拔河。
5. **Phase 2 子实例**：GhostTug→GhostBomb→GhostWraith→GhostElite。
6. **Phase 2→3 过渡动画**：变身流程 + Phase 2 残留清理。
7. **Phase 3 行为树**：禁锢→冲刺→三连斩→踢人→扔镰刀→召唤幽灵。
8. **Phase 3 子实例**：WitchScythe→HellHand→GhostSummon。
9. **死亡流程**。
10. **测试场景**：BossTestArena 搭建。

---

## 23. 关键注意事项（给 AI 的提醒）

1. **CooldownDecorator 不要用**：在 SelectorReactive 路径下会被 interrupt 重置。所有冷却用 CondCooldownReady + blackboard 自管理（见 BEEHAVE_REFERENCE.md 错误 13）。
2. **SequenceReactive 非末尾不放 ActionLeaf**：只有最后一个节点可以返回 RUNNING（见 D-16 规则）。
3. **动画播放用 `anim_play()` 封装**：与修女蛇同款接口，内部走 AnimDriverSpine。
4. **set_animation 直接替换**：不要先 clear_track 再 set_animation（见 SPINE 标准 2.4 节）。
5. **信号用 `animation_completed`**：不用 `animation_ended`（见 SPINE 标准 2.5 节）。
6. **骨骼位置用 `get_bone_world_position()`**：与修女蛇一致。
7. **Area2D 的 monitoring/disabled 用 `set_deferred`**：物理帧内不能直接修改碰撞状态。
8. **Boss 不与 platform 碰撞**：利用 one-way collision 特性，Boss 从上方穿过。
9. **所有子实例生成后 `add_to_group()`**：方便阶段切换和死亡时批量清理。
10. **interrupt() 必须调 `super()`**：且必须幂等（D-04 规则）。
11. **镰刀状态是 Phase 3 行为分叉核心**：`_scythe_in_hand` 决定哪些技能可用。镰刀在外时禁止一切行为，只能原地待机（`idle_no_scythe`）等镰刀回航。镰刀回手后行为树正常重评估，一切解锁。
12. **镰刀回航后无特殊攻击流**：catch_scythe 播完后 ActThrowScythe 返回 SUCCESS，行为树从头重评估。如果玩家在踢人范围内，P3KickSeq 自然触发。
13. **地狱之手 → 奔跑斩击是两步联动**：禁锢成功后 `_player_imprisoned = true`，行为树最高优先级分支自动接管。
14. **玩家冻结/解冻必须配对**：HellHand 和 GhostTug 中 `set_external_control_frozen` 在 `_exit_tree` 和 `interrupt` 中必须确保解冻。
15. **Phase 切换时清理残留**：Phase 2→3 清理全部 Phase 2 实例；死亡时清理全部 7 个 group。
