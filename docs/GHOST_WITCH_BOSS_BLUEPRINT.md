# 幽灵魔女 Boss 工程蓝图（Phase 1 & 2）

> Godot 4.5 · GDScript · Beehave 2.9.2 · Spine-Godot
> 架构模式：参照 `stone_mask_bird` 的 **Mode FSM + Beehave 条件路由**
> Phase 3 另文补充

---

## 0. 名词归一

| 原词 | 工程名 | 说明 |
|---|---|---|
| 幽灵魔女石像 | `BossGhostWitch` | 主场景，继承 MonsterBase |
| 婴儿石像 / 光环 | `BabyStatue` | 魔女子节点，非独立实例 |
| 幽灵拔河 | `GhostTug` | 独立实例，绑定玩家 center3 |
| 自爆幽灵 | `GhostBomb` | 独立实例，S形追踪 |
| 亡灵气流幽灵 | `GhostWraith` | 独立实例，`wraith_type` 参数区分3形态 |
| 精英亡灵 | `GhostElite` | 独立实例，HP=1，打中扣Boss血 |
| realhurtbox | `RealHurtbox` | EnemyHurtbox(4) 变体，仅 `ghost_fist` 有效 |
| bodybox | `BodyBox` | chain 碰到无效，不造成伤害 |

---

## 1. 实体注册与HP

### 注册表（写入 C_ENTITY_DIRECTORY.md）

| species_id | 场景 | attribute | size | HP | 说明 |
|---|---|---|---|---|---|
| `boss_ghost_witch` | `BossGhostWitch.tscn` | NORMAL | LARGE | 30 | 主体 |
| `ghost_tug` | `GhostTug.tscn` | NORMAL | SMALL | 1 | ghostfist 可打断 |
| `ghost_bomb` | `GhostBomb.tscn` | NORMAL | SMALL | 1 | 自爆 + 光照充能 |
| `ghost_wraith` | `GhostWraith.tscn` | NORMAL | SMALL | 1 | 3 型合一 |
| `ghost_elite` | `GhostElite.tscn` | NORMAL | SMALL | 1 | 击中扣 Boss 本体血 |

> 全部子实例：**不可融合、不可 chain 链接、可被 ghostfist 消灭**。融合规则全部 REJECTED。

### HP 模型

- 总 HP = 30。Phase 1 打掉 10 点 (30→20) 变身；Phase 2 打掉 10 点 (20→10) 变身。
- 变身期间 `hp_locked = true` + `invincible = true`。
- **覆盖 MonsterBase 的 weak/stun/vanish**：本 Boss 不使用这些系统。

---

## 2. 碰撞层

| 节点 | layer | mask | 说明 |
|---|---|---|---|
| Boss CharacterBody2D | `4` EnemyBody(3) | `1` World(1) | 仅与 ground 碰撞；platform 用 one-way collision 自然穿过 |
| BodyBox (Area2D) | 无 | 无 | chain 碰到检测到但 `on_chain_hit → 0` 不扣血；不堵路 |
| RealHurtbox (Area2D) | `8` EnemyHurtbox(4) | — | 复用现有层，ghostfist hitbox 的 mask 已包含层4 |
| 各攻击 Hitbox | `32` hazards(6) | `2` PlayerBody(2) | 伤害玩家 |

> **关键**：`apply_hit()` 中判断 `hit.weapon_id == &"ghost_fist"` 才扣血，其余 return false。

---

## 3. 架构概述

### Mode FSM + Beehave 双层驱动

与 `stone_mask_bird` 完全相同的模式：

1. 主脚本维护 `mode` 枚举变量
2. Beehave 树顶层 `SelectorReactiveComposite`，每帧按优先级依次检查 `Cond_ModeIs`
3. **Idle Action** 负责距离/冷却检测 → 满足条件时设 `witch.mode = Mode.XXX`
4. 下一帧 BT 自然路由到对应 **执行 Action**（返回 RUNNING 直到完成）
5. 执行完毕 → `witch.mode = Mode.IDLE` → 回到 Idle 检测

**攻击不可打断**：执行期间 mode 不变，只有匹配的 Sequence 通过条件，其余全 FAILURE。

**冷却管理**：用 `Time.get_ticks_msec() / 1000.0` 时间戳存在主脚本 `next_xxx_sec` 变量。不用 Beehave CooldownDecorator（SelectorReactive 中有 bug，见 BEEHAVE_REFERENCE D-01）。

### Mode 枚举

```gdscript
enum Mode {
    IDLE = 0,
    START_ATTACK = 1,       # P1 开场
    THROW_BABY = 2,         # P1 投掷婴儿
    BABY_ATTACK_FLOW = 3,   # P1 婴儿攻击流
    SCYTHE_SLASH = 4,       # P2 镰刀斩
    FLY_SLAM = 5,           # P2 飞天砸落
    UNDEAD_WIND = 6,        # P2 亡灵气流
    GHOST_TUG = 7,          # P2 幽灵拔河
    PHASE_TRANSITION = 8,   # 变身中（无敌）
    HURT = 16,
    DEATH = 17,
    MOVE_TO_PLAYER = 18,
    # Phase 3 的 Mode 在补充文档中定义
}
```

---

## 4. 主脚本要点 `boss_ghost_witch.gd`

继承 `MonsterBase`，`class_name BossGhostWitch`。

### 4.1 关键导出参数

```gdscript
@export var phase1_detect_range: float = 500.0
@export var p2_scythe_range: float = 100.0
@export var p2_fly_slam_range: float = 500.0
@export var p2_undead_wind_min: float = 100.0
@export var p2_undead_wind_max: float = 300.0
@export var p2_tug_range: float = 500.0  # 大于此值触发拔河

@export var cd_scythe_slash: float = 1.0
@export var cd_fly_slam: float = 3.0
@export var cd_undead_wind: float = 15.0
@export var cd_ghost_tug: float = 5.0
@export var cd_ghost_bomb_spawn: float = 5.0
@export var fly_slam_stun_time: float = 1.0
```

### 4.2 状态变量

```gdscript
var mode: int = Mode.IDLE
var phase: int = 1       # 1 或 2（本文档范围）
var invincible: bool = false
var next_scythe_sec: float = 0.0
var next_fly_slam_sec: float = 0.0
var next_undead_wind_sec: float = 0.0
var next_ghost_tug_sec: float = 0.0
var next_ghost_bomb_sec: float = 0.0
```

### 4.3 关键重写

```gdscript
# 只接受 ghostfist 伤害
func apply_hit(hit: HitData) -> bool:
    if invincible or hp <= 0:
        return false
    if hit.weapon_id != &"ghost_fist":
        _flash_once()
        return false
    hp = max(hp - hit.damage, 0)
    _flash_once()
    _check_phase_transition()
    if hp <= 0:
        mode = Mode.DEATH
    return true

# 禁用 weak/stun/chain
func _update_weak_state() -> void: pass
func apply_stun(_s: float, _f: bool = true) -> void: pass
func on_chain_hit(_p: Node, _s: int) -> int: return 0
```

### 4.4 阶段切换

```gdscript
func _check_phase_transition() -> void:
    if phase == 1 and hp <= 20:
        _start_transition(2)
    elif phase == 2 and hp <= 10:
        _start_transition(3)

func _start_transition(new_phase: int) -> void:
    invincible = true
    hp_locked = true
    mode = Mode.PHASE_TRANSITION
    phase = new_phase
    # Act_PhaseTransition 播放变身动画，完成后 invincible=false, mode=IDLE
```

### 4.5 子节点引用

```gdscript
@onready var baby_statue: Node2D = $BabyStatue
@onready var mark_hug: Marker2D = $MarkHug       # 婴儿抱持位(P1)
@onready var mark_hale: Marker2D = $MarkHale      # 光环位(P2)
@onready var real_hurtbox: Area2D = $RealHurtbox
@onready var body_box: Area2D = $BodyBox
@onready var scythe_hitbox: Area2D = $ScytheHitbox # 镰刀斩 / start_attack 共用
@onready var ground_hitbox: Area2D = $GroundHitbox
```

### 4.6 Spine 动画驱动

参照 `stone_mask_bird` 的双驱动模式（SpineSprite + AnimDriverSpine/Mock）：

```gdscript
# 统一动画接口
func anim_play(name: StringName, loop: bool) -> void:
    # set_animation 替换当前动画（永远不用 clear_track）

# Spine 事件回调
func _on_spine_animation_event(a1, a2, a3, a4) -> void:
    # 解析 spine_event.get_data().get_event_name()
    # 路由到对应逻辑（hitbox 开关、子弹生成等）

# 动画完成回调（用 animation_completed，不用 animation_ended）
func _on_anim_completed(entry) -> void:
    # 通知当前 Action
```

---

## 5. 场景节点树

```
BossGhostWitch (CharacterBody2D)
├── CollisionShape2D                    # EnemyBody(3), mask=World(1)
├── SpineSprite                          # 魔女石像动画
├── BodyBox (Area2D)                     # chain 碰到无效
│   └── CollisionShape2D
├── RealHurtbox (Area2D)                 # 层4, 仅 ghostfist 有效
│   └── CollisionShape2D                 # P1 绑 baby core 骨骼; P2 绑魔女 hale 骨骼
├── ScytheHitbox (Area2D)                # 镰刀斩 / start_attack 共用
│   └── CollisionShape2D
├── GroundHitbox (Area2D)                # P2 砸地范围伤害
│   └── CollisionShape2D
├── MarkHug (Marker2D)                   # 婴儿抱持位
├── MarkHale (Marker2D)                  # 光环绑定位
├── BabyStatue (Node2D)                  # 婴儿石像子节点
│   ├── SpineSprite                      # 婴儿/光环动画
│   ├── BabyBodyBox (Area2D)             # 婴儿 bodybox
│   ├── BabyRealHurtbox (Area2D)         # 绑 core 骨骼, 层4
│   ├── BabyExplosionHitbox (Area2D)     # 爆炸范围伤害
│   └── BabySlashHitbox (Area2D)         # 攻击流1 斩击
└── BeehaveTree                          # 行为树
```

---

## 6. 攻击总表

### Phase 1

| 攻击 | 范围px | 冷却 | 伤害 | 备注 |
|---|---|---|---|---|
| 开场一击 | 近身 | 一次性 | 1 | 首次检测到玩家 |
| 投掷婴儿 | 500 | 依赖返航 | 0 | 唯一主动攻击 |
| 婴儿爆炸 | 小范围 | - | 1 | 撞地面/玩家触发 |
| 攻击流1(冲刺+斩击) | 路径 | - | 各1 | 婴儿修复后自动 |

### Phase 2（优先级 1=最高）

| # | 攻击 | 范围px | 冷却s | 伤害 | 优先级 |
|---|---|---|---|---|---|
| 1 | 镰刀斩 | ≤100 | 1 | 1 | 1 |
| 2 | 飞天砸落 | ≤500 | 3 | 1(落地) | 2 |
| 3 | 亡灵气流 | 100~300 | 15 | 碰撞1 | 3 |
| 4 | 幽灵拔河 | >500 | 5 | 0(拉拽) | 4 |
| 被动 | 自爆幽灵 | 追踪 | 5 | 1+光照+5 | 空闲时 |
| 被动 | 向玩家移动 | - | - | 0 | 冷却中 |

---

## 7. Beehave 行为树（Phase 1 & 2 部分）

```
BeehaveTree (process_thread=PHYSICS)
└── RootSelector (SelectorReactiveComposite)     ← 每帧从顶部重新评估
    │
    ├── [1] Seq_Death
    │   ├── Cond_ModeIs(DEATH)
    │   └── Act_Death
    │
    ├── [2] Seq_PhaseTransition
    │   ├── Cond_ModeIs(PHASE_TRANSITION)
    │   └── Act_PhaseTransition
    │
    ├── [3] Seq_Hurt
    │   ├── Cond_ModeIs(HURT)
    │   └── Act_Hurt
    │
    └── [4] PhaseRouter (SelectorComposite)      ← 非 Reactive, 只走一个
        │
        ├── Seq_Phase1
        │   ├── Cond_PhaseIs(1)
        │   └── P1Sel (SelectorReactiveComposite)
        │       ├── Seq: Cond_ModeIs(START_ATTACK) → Act_StartAttack
        │       ├── Seq: Cond_ModeIs(THROW_BABY) → Act_ThrowBaby
        │       ├── Seq: Cond_ModeIs(BABY_ATTACK_FLOW) → Act_BabyAttackFlow
        │       └── Seq: Cond_ModeIs(IDLE) → Act_P1Idle
        │
        └── Seq_Phase2
            ├── Cond_PhaseIs(2)
            └── P2Sel (SelectorReactiveComposite)
                ├── Seq: Cond_ModeIs(SCYTHE_SLASH) → Act_ScytheSlash
                ├── Seq: Cond_ModeIs(FLY_SLAM) → Act_FlySlam
                ├── Seq: Cond_ModeIs(UNDEAD_WIND) → Act_UndeadWind
                ├── Seq: Cond_ModeIs(GHOST_TUG) → Act_GhostTug
                ├── Seq: Cond_ModeIs(MOVE_TO_PLAYER) → Act_MoveToPlayer
                └── Seq: Cond_ModeIs(IDLE) → Act_P2Idle
```

### 条件节点模板（`cond_mode_is.gd` / `cond_phase_is.gd`）

```gdscript
extends ConditionLeaf
@export var target_mode: int = 0

func tick(actor: Node, _bb: Blackboard) -> int:
    var w := actor as BossGhostWitch
    if w == null: return FAILURE
    return SUCCESS if w.mode == target_mode else FAILURE
```

`cond_phase_is.gd` 同理，检查 `w.phase == target_phase`。

### Action 节点模板

所有 Action 遵循相同骨架（参照 stone_mask_bird）：

```gdscript
extends ActionLeaf

enum Phase { INIT, EXEC, END }
var _phase: int = Phase.INIT

func before_run(actor: Node, _bb: Blackboard) -> void:
    _phase = Phase.INIT
    # 初始化本次攻击状态

func tick(actor: Node, _bb: Blackboard) -> int:
    var w := actor as BossGhostWitch
    if w == null: return FAILURE
    match _phase:
        Phase.INIT: return _tick_init(w)
        Phase.EXEC: return _tick_exec(w)
        Phase.END:  return _tick_end(w)
    return RUNNING

func interrupt(actor: Node, bb: Blackboard) -> void:
    # 清理临时状态
    super(actor, bb)
```

---

## 8. Phase 1 详细行为

### 8.1 Act_P1Idle

检测逻辑（每帧 RUNNING）：

```
首次检测到玩家 → witch.mode = START_ATTACK; return SUCCESS
婴儿已返航 + 玩家≤500px → witch.mode = THROW_BABY; return SUCCESS
玩家不在范围 + 未投掷婴儿 → 缓慢向玩家 walk 移动（投掷后禁止移动）
return RUNNING
```

### 8.2 Act_StartAttack

内部状态：`ANIM → LOOP → EXTER`

```
ANIM:
  anim_play("phase1/start_attack", false)
  Spine事件 start_attack_hitbox_on → scythe_hitbox.monitoring = true
  Spine事件 start_attack_hitbox_off → scythe_hitbox.monitoring = false
  animation_completed → 进入 LOOP

LOOP:
  anim_play("phase1/start_attack_loop", true)
  计时 4 秒
  超时 → 进入 EXTER

EXTER:
  anim_play("phase1/start_attack_exter", false)
  animation_completed → witch.mode = IDLE; return SUCCESS
```

### 8.3 Act_ThrowBaby — 婴儿石像完整生命周期

这是 Phase 1 最复杂的 Action，内部管理婴儿从投掷到返航的全流程。

#### 内部状态机

```
THROW → FLY → EXPLODE → REPAIR → ATTACK_FLOW → RETURN
```

#### THROW

```
anim_play("phase1/throw", false)
baby_release 事件时:
  baby.visible = true
  baby.reparent(get_parent())  # 临时脱离魔女，自由移动
  baby.global_position = mark_hug.global_position
  目标 = 玩家当前位置

魔女切 phase1/idle_no_baby
→ 进入 FLY
```

#### FLY

```
baby 播放 baby/fly_loop
baby 以抛物线/直线飞向目标位置
碰到地面(is_on_floor) 或 碰到玩家(area检测) → 进入 EXPLODE
```

> 判断方式：婴儿用 CharacterBody2D 或单纯用 `_physics_process` 做位移 + Area2D 检测。推荐纯位移 + Area2D，不需要给婴儿做 CharacterBody2D（它是魔女子节点）。

#### EXPLODE

```
baby 播放 baby/explode
explode_hitbox_on 事件 → BabyExplosionHitbox.monitoring = true（范围伤害）
explode_hitbox_off 事件 → BabyExplosionHitbox.monitoring = false
realhurtbox_on 事件 → BabyBodyBox 关闭, BabyRealHurtbox.monitoring = true
→ 进入 REPAIR
```

#### REPAIR

```
baby 播放 baby/repair（非 loop）
期间玩家 ghostfist 打中 BabyRealHurtbox → witch.apply_hit() 扣本体血 + 魔女播 phase1/hurt
（修复期间被打只闪白，不改变婴儿行为状态）
realhurtbox_off 事件 → BabyRealHurtbox.monitoring = false
repair_done 事件 → 进入 ATTACK_FLOW
```

#### ATTACK_FLOW（攻击流1）

```
记录 posA = 婴儿当前位置
记录 posB = 玩家当前位置

1. 冲刺 A→B:
   baby 播放 baby/dash
   baby 向 posB 快速移动
   dash_hitbox_on → 碰到玩家 hp-1
   到达 posB → dash_hitbox_off

2. 斩击:
   baby 播放 baby/slash
   slash_hitbox_on → 范围伤害
   slash_hitbox_off → 关闭

3. 冲刺 B→A:
   baby 播放 baby/dash
   向 posA 移动（碰到同样伤害）
   到达 posA → 进入 RETURN
```

#### RETURN

```
baby 播放 baby/return
baby 向 mark_hug.global_position 飞行
到达后:
  baby.reparent(witch)
  baby.position = mark_hug.position（局部坐标）
  魔女播 phase1/catch_baby → phase1/idle
  witch.mode = IDLE; return SUCCESS
```

### 8.4 婴儿 RealHurtbox → Boss 本体扣血路径

```gdscript
# baby_statue.gd 或主脚本中
func _on_baby_real_hurtbox_area_entered(hitbox: Area2D) -> void:
    # hitbox 是 ghostfist 的攻击区域
    var host: Node = hitbox.get_parent()  # 或其他方式获取 player
    if host == null: return
    # 创建 HitData，weapon_id = "ghost_fist"
    var hit := HitData.create(1, host as Node2D, &"ghost_fist", HitData.Flags.NONE)
    witch.apply_hit(hit)  # 扣主体血
    witch.anim_play(&"phase1/hurt", false)  # 魔女播受击动画
```

### 8.5 Phase 1→2 切换（Act_PhaseTransition, phase==2）

```
1. 立刻：婴儿播 baby/phase1_to_phase2
   become_halo 事件时:
     BabyBodyBox 永久关闭 (monitoring=false)
     BabyRealHurtbox 永久开启 (monitoring=true)
     婴儿绑定位从 mark_hug 改为 mark_hale

2. 如果婴儿当前在场上（未返航）→ 先飞向 mark_hale

3. 光环到达 mark_hale → 魔女播 phase1_to_phase2
   phase2_ready 事件时:
     baby_statue.visible = false（光环已含在魔女 phase2 动画中）
     RealHurtbox 换绑到魔女 SpineSprite 的 hale 骨骼
     （每帧用 get_global_bone_transform("hale") 同步位置）

4. invincible = false; hp_locked = false; mode = IDLE
```

---

## 9. Phase 2 详细行为

### 9.1 Act_P2Idle — 核心决策器

每帧执行，按优先级检测（RUNNING 保持循环）：

```gdscript
func tick(actor: Node, _bb: Blackboard) -> int:
    var w := actor as BossGhostWitch
    var now := Time.get_ticks_msec() / 1000.0
    var player := w.get_priority_attack_target()
    if player == null: return RUNNING
    var dist := absf(w.global_position.x - player.global_position.x)

    # 优先级1: 近身镰刀斩
    if dist <= w.p2_scythe_range and now >= w.next_scythe_sec:
        w.mode = BossGhostWitch.Mode.SCYTHE_SLASH
        return SUCCESS

    # 优先级2: 飞天砸落
    if dist <= w.p2_fly_slam_range and now >= w.next_fly_slam_sec:
        w.mode = BossGhostWitch.Mode.FLY_SLAM
        return SUCCESS

    # 优先级3: 亡灵气流
    if dist > w.p2_undead_wind_min and dist <= w.p2_undead_wind_max \
       and now >= w.next_undead_wind_sec:
        w.mode = BossGhostWitch.Mode.UNDEAD_WIND
        return SUCCESS

    # 优先级4: 幽灵拔河
    if dist > w.p2_tug_range and now >= w.next_ghost_tug_sec:
        w.mode = BossGhostWitch.Mode.GHOST_TUG
        return SUCCESS

    # 被动: 冷却中向玩家移动
    _move_toward_player(w, player)

    # 被动: 自爆幽灵生成
    if now >= w.next_ghost_bomb_sec:
        var bomb_count := w.get_tree().get_nodes_in_group("ghost_bomb").size()
        if bomb_count < 3:
            _spawn_ghost_bomb(w)
            w.next_ghost_bomb_sec = now + w.cd_ghost_bomb_spawn

    return RUNNING
```

### 9.2 Act_ScytheSlash

```
before_run: witch.anim_play("phase2/scythe_slash", false)

Spine事件:
  scythe_hitbox_on → scythe_hitbox.monitoring = true
  scythe_hitbox_off → scythe_hitbox.monitoring = false

animation_completed → next_scythe_sec = now + cd; mode = IDLE; return SUCCESS
```

### 9.3 Act_FlySlam

内部状态：`LIFT → FALL → LAND → STUN`

```
LIFT:
  目标位置 = (player.x ± 70px随机, player.y - 400px)
  witch 快速移动到目标位置（用 Tween 或每帧 lerp）
  anim_play("phase2/fly_slam_rise", false)
  到达目标 → 进入 FALL

FALL:
  anim_play("phase2/fly_slam_fall", false)
  0.5 秒加速下落（先慢后快）:
    var t := elapsed / 0.5
    velocity.y = lerpf(100.0, 2000.0, t * t)  # 二次加速
  穿过 platform（one-way collision 从上方自然穿过）
  is_on_floor() → 进入 LAND

LAND:
  anim_play("phase2/fly_slam_land", false)
  ground_hitbox.monitoring = true  # 范围伤害
  1帧后 ground_hitbox.monitoring = false
  → 进入 STUN

STUN:
  等待 fly_slam_stun_time 秒（僵直）
  → next_fly_slam_sec = now + cd; mode = IDLE; return SUCCESS
```

### 9.4 Act_UndeadWind

内部状态：`ENTER → SPAWN_LOOP → EXIT`

```
ENTER:
  real_hurtbox.monitorable = false  # 不可被攻击
  anim_play("phase2/undead_wind_enter", false)
  animation_completed → 进入 SPAWN_LOOP

SPAWN_LOOP:
  anim_play("phase2/undead_wind_loop", true)
  7秒内生成10只 GhostWraith:
    type 按 1→2→3→1→2→3... 循环
    间隔逐渐缩短: interval = lerp(1.2, 0.3, spawned/10.0)
    随机在第 N 只(随机)时生成1只 GhostElite 替代
  7秒结束 → 进入 EXIT

EXIT:
  anim_play("phase2/undead_wind_exit", false)
  real_hurtbox.monitorable = true  # 恢复可被攻击
  animation_completed → next_undead_wind_sec = now + cd; mode = IDLE; return SUCCESS
```

**GhostWraith 脚本要点**（`ghost_wraith.gd`）：
- `@export var wraith_type: int = 1` → 播放 `type1/move` 或 `type2/move` 或 `type3/move`
- `velocity.x = signf(player.x - position.x) * speed`（X轴向平移）
- 10秒后 `queue_free()`
- ghostfist 命中 → `queue_free()`
- 加入 `"ghost_wraith"` 组

**GhostElite 脚本要点**（`ghost_elite.gd`）：
- HP = 1，ghostfist 命中 → `boss_ref.apply_hit(hit)` + `queue_free()`
- 有 DetectArea，玩家在范围内 → 挥击(SlashHitbox, 冷却1s, Spine事件驱动)
- 加入 `"ghost_elite"` 组

### 9.5 Act_GhostTug

内部状态：`CAST → PULLING → END`

```
CAST:
  anim_play("phase2/ghost_tug_enter", false)
  tug_spawn 事件 → 生成 GhostTug 实例:
    tug.reparent(player.get_node("center3"))  # 绑定玩家
    tug.position = Vector2.ZERO
    tug.witch_ref = witch
    tug.setup(witch.global_position)
  animation_completed → 进入 PULLING
  anim_play("phase2/ghost_tug_loop", true)

PULLING:
  每帧检查:
    if tug被销毁(ghostfist打断):
      next_ghost_tug_sec = now + cd; mode = IDLE; return SUCCESS
    if 玩家进入 scythe_hitbox 检测区:
      tug.queue_free()
      mode = SCYTHE_SLASH; return SUCCESS  # 立刻镰刀斩
  return RUNNING

END:
  anim_play("phase2/ghost_tug_exit", false)
  → mode = IDLE; return SUCCESS
```

**GhostTug 脚本要点**（`ghost_tug.gd`）：
```gdscript
var witch_ref: Node2D
var pull_speed: float = 400.0  # 可调

# Spine 动画 move_loop 的 move 事件回调
func _on_move_event() -> void:
    var player := get_parent().get_parent() as Node2D  # center3 的父节点
    if player == null or witch_ref == null: return
    var dir_x := signf(witch_ref.global_position.x - player.global_position.x)
    player.velocity.x = dir_x * pull_speed

# ghostfist 命中
func _on_hurtbox_area_entered(_hitbox: Area2D) -> void:
    queue_free()  # Boss 的 Act_GhostTug 会在下帧检测到消失
```

> **拉拽原理**：直接设 `player.velocity.x`。不需要修改 player 脚本。这与 `act_seb_attack.gd` 中直接操作 velocity 的先例一致。玩家被拉时不播放 run/walk 动画（velocity 被外力覆盖，locomotion FSM 会根据 velocity 自动处理）。

### 9.6 被动：自爆幽灵

在 `Act_P2Idle` 中管理（见 §9.1），每 5 秒空闲时生成，场上最多 3 只。

**GhostBomb 脚本要点**（`ghost_bomb.gd`）：
```gdscript
# 移动：S形蛇形
func _physics_process(dt: float) -> void:
    _alive_time += dt
    if _retarget_timer <= 0.0:
        _target_dir = signf(player.global_position.x - global_position.x)
        _retarget_timer = 2.0  # 每2秒更新方向
    _retarget_timer -= dt
    velocity.x = _target_dir * move_speed
    velocity.y = sinf(_alive_time * wave_freq) * wave_amp
    move_and_slide()

# 碰到玩家 → 1秒自爆倒计时
func _on_damage_area_body_entered(body: Node2D) -> void:
    if body.is_in_group("player"):
        _start_self_destruct()

func _self_destruct() -> void:
    damage_area.monitoring = true   # 伤害区（hazards层）
    light_area.monitoring = true    # 光照区（独立 Area2D）
    # 光照效果：参考 LightningFlower，energy +5
    EventBus.emit_healing_burst(5.0)
    queue_free()
```

> **关键**：DamageArea（伤害）和 LightArea（光照充能）是**两个独立 Area2D**，范围可不同。

### 9.7 Phase 2→3 切换

在 `Act_PhaseTransition`（phase==3）中处理：

```
1. 魔女播 phase2_to_phase3
2. shatter 事件 → VFX 碎裂
3. EventBus.emit_boss_ghost_bomb_cleanup() → 场上所有 GhostBomb queue_free()
4. phase3_ready 事件 → RealHurtbox 换绑新骨骼
5. 切 phase3/idle
6. invincible = false; mode = IDLE
```

---

## 10. 动画清单

### 魔女石像 SpineSprite

| 动画 | Loop | 事件 |
|---|---|---|
| `phase1/idle` | Y | — |
| `phase1/idle_no_baby` | Y | — |
| `phase1/walk` | Y | `footstep` |
| `phase1/start_attack` | N | `start_attack_hitbox_on`, `start_attack_hitbox_off` |
| `phase1/start_attack_loop` | Y | — |
| `phase1/start_attack_exter` | N | `battle_start` |
| `phase1/throw` | N | `baby_release`, `baby_visible` |
| `phase1/catch_baby` | N | `baby_catch` |
| `phase1/hurt` | N | — |
| `phase1_to_phase2` | N | `stand_up`, `phase2_ready` |
| `phase2/idle` | Y | — |
| `phase2/walk` | Y | `footstep` |
| `phase2/scythe_slash` | N | `scythe_hitbox_on`, `scythe_hitbox_off` |
| `phase2/fly_slam_rise` | N | — |
| `phase2/fly_slam_fall` | N | — |
| `phase2/fly_slam_land` | N | `ground_hitbox_on`, `ground_hitbox_off` |
| `phase2/undead_wind_enter` | N | `wind_start`, `realhurtbox_off` |
| `phase2/undead_wind_loop` | Y | `spawn_wraith` |
| `phase2/undead_wind_exit` | N | `realhurtbox_on` |
| `phase2/ghost_tug_enter` | N | `tug_spawn` |
| `phase2/ghost_tug_loop` | Y | — |
| `phase2/ghost_tug_exit` | N | — |
| `phase2/hurt` | N | — |
| `phase2_to_phase3` | N | `shatter`, `phase3_ready` |

### 婴儿石像 SpineSprite

| 动画 | Loop | 事件 |
|---|---|---|
| `baby/fly_loop` | Y | — |
| `baby/explode` | N | `explode_hitbox_on`, `explode_hitbox_off`, `realhurtbox_on` |
| `baby/debris_loop` | Y | — |
| `baby/repair` | N | `realhurtbox_off`, `repair_done` |
| `baby/dash` | N | `dash_hitbox_on`, `dash_hitbox_off` |
| `baby/slash` | N | `slash_hitbox_on`, `slash_hitbox_off` |
| `baby/return` | N | `return_done` |
| `baby/phase1_to_phase2` | N | `transform_start`, `become_halo` |
| `baby/halo_idle` | Y | — |

---

## 11. 子实例场景结构

### GhostTug.tscn
```
GhostTug (Node2D)
├── SpineSprite         # move_loop 动画 + move 事件
└── TugHurtbox (Area2D) # 层4, ghostfist 打断点
    └── CollisionShape2D
```

### GhostBomb.tscn
```
GhostBomb (CharacterBody2D)
├── CollisionShape2D
├── SpineSprite
├── DamageArea (Area2D)  # 层6 hazards, 伤害
├── LightArea (Area2D)   # 独立光照区（与伤害分开）
└── Hurtbox (Area2D)     # 层4, ghostfist 可打
    └── CollisionShape2D
```

### GhostWraith.tscn（3型合一）
```
GhostWraith (CharacterBody2D)
├── SpineSprite          # wraith_type 决定播放 type1/ type2/ type3/
├── DamageArea (Area2D)  # 碰撞伤害
└── Hurtbox (Area2D)     # ghostfist 可消灭
```

### GhostElite.tscn
```
GhostElite (CharacterBody2D)
├── SpineSprite
├── DamageArea (Area2D)   # 碰撞伤害
├── SlashHitbox (Area2D)  # 挥击范围攻击（冷却1s）
├── DetectArea (Area2D)   # 玩家范围检测
└── Hurtbox (Area2D)      # ghostfist 打中 → boss.apply_hit + queue_free
```

---

## 12. EventBus 新增信号

```gdscript
signal boss_phase_changed(boss: Node, new_phase: int)
signal boss_ghost_bomb_cleanup()      # Phase 2 结束清理自爆幽灵
```

> 每个信号配套 `emit_*()` 封装方法。

---

## 13. 关键注意事项

1. **Spine 切动画**：永远 `set_animation()` 替换，禁止 `clear_track()` 再设置（会冻结骨骼）
2. **Spine 事件**：`animation_event` 信号 → `spine_event.get_data().get_event_name()`
3. **动画完成**：用 `animation_completed`（不是 `animation_ended`）
4. **RealHurtbox 骨骼同步**：`_physics_process` 中 `get_global_bone_transform("bone_name")` 每帧同步
5. **冷却**：`Time.get_ticks_msec() / 1000.0` 时间戳，不用 CooldownDecorator
6. **攻击承诺锁**：参考 `stone_mask_bird` 的 `shoot_face_committed`，攻击期间条件始终 SUCCESS
7. **拉拽**：直接设 `player.velocity.x`（`act_seb_attack.gd` 先例）
8. **婴儿 reparent**：投掷时 `reparent(get_parent())` 自由移动；返航后 `reparent(witch)` 回来
9. **子实例分组**：各子实例加入对应 group（`ghost_bomb`、`ghost_wraith` 等），方便批量清理

---

## 14. 文件目录

```
scene/enemies/boss_ghost_witch/
├── BossGhostWitch.tscn
├── boss_ghost_witch.gd
├── bt_boss_ghost_witch.tscn
├── baby_statue.gd
├── actions/
│   ├── act_p1_idle.gd
│   ├── act_start_attack.gd
│   ├── act_throw_baby.gd        # 包含婴儿完整生命周期
│   ├── act_baby_attack_flow.gd
│   ├── act_p2_idle.gd           # 包含被动技能管理
│   ├── act_scythe_slash.gd
│   ├── act_fly_slam.gd
│   ├── act_undead_wind.gd
│   ├── act_ghost_tug.gd
│   ├── act_phase_transition.gd
│   ├── act_death.gd
│   ├── act_hurt.gd
│   └── act_move_to_player.gd
├── conditions/
│   ├── cond_mode_is.gd
│   └── cond_phase_is.gd
└── sub_instances/
    ├── GhostTug.tscn / ghost_tug.gd
    ├── GhostBomb.tscn / ghost_bomb.gd
    ├── GhostWraith.tscn / ghost_wraith.gd
    └── GhostElite.tscn / ghost_elite.gd
```
