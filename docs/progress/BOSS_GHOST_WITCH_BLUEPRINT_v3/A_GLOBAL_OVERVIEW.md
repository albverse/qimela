# 《幽灵魔女 BossGhostWitch》工程蓝图 — A. 全局概览

> 本文档是三部曲的第一部，包含所有阶段共用的基础设定、节点结构、主脚本骨架。
> 制作任何阶段之前必须先读本文档。
> **B. Phase 1 & 2 设计** — 详细的 P1/P2 行为树、ActionLeaf、子实例、过渡流程。
> **C. Phase 3 设计** — P3 行为树、ActionLeaf、子实例、死亡流程。

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


---

# ═══ 以下为全三阶段统合表（跨阶段参考）═══

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
