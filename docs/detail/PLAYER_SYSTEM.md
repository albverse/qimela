# Player 系统详解

> 源文件：`scene/player.gd` 及 `scene/components/` 下的各子系统脚本

---

## 1. 总体架构：调度总线模式

Player（`player.gd`）**不是**一个包含所有逻辑的巨型类。它的核心角色是 **调度总线（Dispatch Bus）**，职责可概括为四个方面：

1. **缓存组件引用** — 在 `_ready()` 中获取所有子系统的引用并完成安全校验
2. **维护固定 tick 顺序** — 在 `_physics_process()` 中按严格顺序调用各子系统
3. **转发输入** — 在 `_unhandled_input()` 中将按键事件路由到正确的子系统
4. **统一日志** — 通过 `log_msg()` 提供带帧号、状态快照的格式化输出

### 1.1 组件引用表

```gdscript
var movement:          PlayerMovement       # 水平移动 / 重力 / 跳跃冲量
var loco_fsm:          PlayerLocomotionFSM  # 移动层状态机
var action_fsm:        PlayerActionFSM      # 动作覆盖层状态机
var chain_sys                               # ChainSystem（兼容 stub 与完整版，不强转类型）
var health:            PlayerHealth          # HP / 无敌帧 / 击退
var animator:          PlayerAnimator        # 动画裁决与播放
var weapon_controller: WeaponController      # 武器管理与动画选择
```

### 1.2 物理帧 tick 顺序

每个 `_physics_process(dt)` 严格按以下顺序执行，**顺序不可调换**：

| 步骤 | 子系统 | 职责 |
|:----:|--------|------|
| 1 | `movement.tick(dt)` | 读取输入 → 计算水平速度 / 重力 / 消费 jump_request |
| 2 | `move_and_slide()` | Godot 物理引擎更新（此后 `is_on_floor()` 才准确） |
| 3 | `loco_fsm.tick(dt)` | 读取 floor / vy / intent，评估移动层状态转移 |
| 4 | `action_fsm.tick(dt)` | 全局死亡检查 + 超时保护 + 延迟 fire 提交 |
| 5 | `health.tick(dt)` | 无敌帧倒计时 / 击退飞行更新 |
| 6 | `animator.tick(dt)` | 动画裁决与播放 |
| 7 | `chain_sys.tick(dt)` | 链条物理更新（在 Animator 之后，确保读取当帧骨骼锚点） |
| 8 | `_commit_pending_chain_fire()` | 延迟提交链条发射请求（见下文） |

```gdscript
# player.gd — _physics_process 核心流程
func _physics_process(dt: float) -> void:
    # Die 状态守卫（清理链条、治愈精灵）
    ...
    movement.tick(dt)            # 步骤 1
    move_and_slide()             # 步骤 2
    loco_fsm.tick(dt)            # 步骤 3
    action_fsm.tick(dt)          # 步骤 4
    if health != null:
        health.tick(dt)          # 步骤 5
    animator.tick(dt)            # 步骤 6
    if chain_sys.has_method("tick"):
        chain_sys.call("tick", dt)  # 步骤 7
    _commit_pending_chain_fire()    # 步骤 8
    _block_chain_fire_this_frame = false
```

---

## 2. 关键架构决策

### 2.1 链条发射的延迟提交模式（Deferred Commit）

链条（Chain）发射请求 **不在输入事件中立即执行**，而是写入 `_pending_chain_fire_side`，在物理帧末尾由 `_commit_pending_chain_fire()` 统一提交。

**原因**：避免同帧竞态条件 — 如果输入事件和伤害/死亡发生在同一帧，先提交 fire 后触发 die 会导致"幽灵链条"（ghost chain）。

```gdscript
var _pending_chain_fire_side: String = ""   # "R" / "L" / ""
var _block_chain_fire_this_frame: bool = false

func _commit_pending_chain_fire() -> void:
    if _pending_chain_fire_side == "":
        return
    if _is_chain_fire_blocked():
        _pending_chain_fire_side = ""
        return
    # ... 槽位校验后执行 chain_sys.fire()
    _pending_chain_fire_side = ""
```

### 2.2 同帧受击保护

`_block_chain_fire_this_frame` 在 `_on_health_damage_applied()` 中置 `true`，阻止当帧的链条发射，在物理帧末尾重置为 `false`：

```gdscript
func _on_health_damage_applied(_amount: int, _source_pos: Vector2) -> void:
    _block_chain_fire_this_frame = true
    _pending_chain_fire_side = ""
    action_fsm.on_damaged()
```

### 2.3 玩家锁定机制

`_player_locked` 用于在融合（Fuse）和死亡（Die）等状态下冻结水平输入：

```gdscript
func is_horizontal_input_locked() -> bool:
    if _player_locked:          return true
    if action_fsm.state == PlayerActionFSM.State.DIE:  return true
    if health.is_knockback_active():                    return true
    return false
```

### 2.4 外部眩晕（Stun）

`apply_stun(seconds)` 供外部系统（如 ChimeraStoneSnake 子弹）调用。效果为冻结输入和动作，不造成伤害，实现方式是让 ActionFSM 进入 HURT 状态并临时覆盖超时时间：

```gdscript
func apply_stun(seconds: float) -> void:
    if seconds <= 0.0: return
    if action_fsm.state == PlayerActionFSM.State.DIE: return
    action_fsm.on_stunned(seconds)
```

---

## 3. Movement 移动系统

> 源文件：`scene/components/player_movement.gd`

Movement 组件是一个纯数据驱动的速度计算器，**禁止**直接处理跳跃、状态机转移或播放动画。

### 3.1 MoveIntent 枚举

```gdscript
enum MoveIntent { NONE, WALK, RUN }
# NONE = 0, WALK = 1, RUN = 2
```

| 值 | 含义 | 输入条件 |
|:--:|------|----------|
| `NONE (0)` | 静止 | 无方向键按下 |
| `WALK (1)` | 步行 | A/D 方向键按下 |
| `RUN (2)` | 跑步 | A/D + Shift 同时按下 |

### 3.2 tick 流程

每帧 `tick(dt)` 按以下顺序执行：

1. **Die 状态检查** — 若 ActionFSM 处于 DIE 状态，立即冻结所有移动，归零上抛速度，仅保留重力下落
2. **读取输入** — A/D 决定 `input_dir`（-1/0/+1），Shift 决定是否 RUN
3. **更新 move_intent** — 根据 `input_dir` 和 Shift 组合确定意图
4. **更新 facing** — 仅在有输入时更新朝向（1 或 -1）
5. **水平速度** — 若 `is_horizontal_input_locked()` 为 true 则归零，否则 `input_dir * speed`
6. **重力** — `velocity.y += gravity * dt`
7. **消费 jump_request** — 由 LocomotionFSM 设置，Movement 消费并施加跳跃冲量
8. **落地 vy 夹断** — `is_on_floor() and vy > 0` 时归零，防止重力累积

```gdscript
# 跳跃冲量入口（单一入口，由 LocomotionFSM 请求）
if _player.jump_request:
    _player.velocity.y = -_player.jump_speed
    _player.jump_request = false
```

### 3.3 水平输入锁定

以下情况下水平输入被锁定（`velocity.x = 0`）：

- `_player_locked == true`（融合/死亡时由 Player 设置）
- ActionFSM 处于 `DIE` 状态
- 击退（knockback）激活中

---

## 4. LocomotionFSM 移动层状态机

> 源文件：`scene/components/player_locomotion_fsm.gd`

LocomotionFSM 管理玩家的 **移动层** 状态，与 ActionFSM（动作覆盖层）正交。它只读取物理状态（floor / vy / intent），**禁止**改变 velocity 或播放动画。

### 4.1 状态定义

```gdscript
enum State { IDLE, WALK, RUN, JUMP_UP, JUMP_LOOP, JUMP_DOWN, DEAD }
```

| 状态 | 说明 |
|------|------|
| `IDLE` | 地面静止 |
| `WALK` | 地面步行 |
| `RUN` | 地面跑步 |
| `JUMP_UP` | 跳跃上升段 |
| `JUMP_LOOP` | 空中滞留/下落段 |
| `JUMP_DOWN` | 落地缓冲段 |
| `DEAD` | 死亡终态 |

### 4.2 状态转移图

```
地面态互切（on_floor == true）:

  IDLE ──intent=Walk──▶ WALK ──intent=Run──▶ RUN
   ▲                      │                    │
   └──intent=None─────────┘                    │
   └──intent=None──────────────────────────────┘
   └──intent=Walk──────────────────────────────┘ (RUN→WALK)

跳跃流程:

  地面态(IDLE/WALK/RUN) ──W_pressed──▶ JUMP_UP
                                          │
                              vy>=0 或 anim_end ──▶ JUMP_LOOP
                                                        │
                                              touch_floor ──▶ JUMP_DOWN
                                                                │
                                                    anim_end / 超时 ──▶ IDLE/WALK/RUN

走下平台:

  地面态(IDLE/WALK/RUN) ──leave_ground──▶ JUMP_LOOP

死亡:

  任意状态 ──action_fsm=Die──▶ DEAD（终态，不处理任何逻辑）
```

### 4.3 关键保护机制

**Jump_down 超时保护**：JUMP_DOWN 状态维护一个 1 秒超时计时器，防止落地动画未正常结束导致的卡死：

```gdscript
var _jump_timeout: float = 1  # 1秒超时
var _jump_timer: float = 0.0

if state == State.JUMP_DOWN:
    _jump_timer += _dt
    if _jump_timer > _jump_timeout:
        _do_transition(State.IDLE, "jump_down_timeout", 99, ...)
        return
```

**vy_fallback**：JUMP_UP 状态下，若 `vy >= 0`（已开始下落）但跳跃上升动画尚未结束，强制切换到 JUMP_LOOP：

```gdscript
if state == State.JUMP_UP and not on_floor and vy >= 0.0:
    _do_transition(State.JUMP_LOOP, "vy_fallback", 3, ...)
```

**leave_ground 检测**：从地面走下平台（非主动跳跃）时，自动进入 JUMP_LOOP：

```gdscript
if not on_floor and _prev_on_floor:
    if state in [State.IDLE, State.WALK, State.RUN]:
        _do_transition(State.JUMP_LOOP, "leave_ground", 3, ...)
```

---

## 5. ActionFSM 动作覆盖层状态机

> 源文件：`scene/components/player_action_fsm.gd`

ActionFSM 管理需要 **打断或覆盖** 正常移动的动作（攻击、受伤、融合、死亡），与 LocomotionFSM 正交运行。

### 5.1 状态定义与优先级

```gdscript
enum State { NONE, ATTACK, ATTACK_CANCEL, FUSE, HURT, DIE }
```

| 状态 | 优先级 | 说明 |
|------|:------:|------|
| `DIE` | 100 | 死亡终态 — 清空所有链条、冻结移动、通知 Health |
| `FUSE` | 95 | 融合施法（Chain 武器专属，双槽位 LINKED 后触发） |
| `HURT` | 90 | 受伤/僵直 — 含外部 stun（不扣血） |
| `ATTACK_CANCEL` | 6 | 攻击取消（X 键中断攻击） |
| `ATTACK` | 5 | 攻击中（Sword/Knife 走此路径；Chain 绕过 ActionFSM） |
| `NONE` | 0 | 空闲（无动作覆盖） |

### 5.2 武器路径分流

这是一个重要的架构决策：

- **Sword / Knife**：通过 `on_m_pressed()` 进入 ActionFSM 的 ATTACK 状态
- **Chain**：**绕过 ActionFSM**，由 `player.gd` 的输入处理直接写入 `_pending_chain_fire_side`，通过 ChainSystem 发射

```
鼠标左键 / F 键:
  ├─ 当前武器 == CHAIN → player.gd 排队到 _pending_chain_fire_side（绕过 ActionFSM）
  └─ 当前武器 == SWORD/KNIFE → action_fsm.on_m_pressed()（走 ActionFSM 标准流程）
```

### 5.3 Die 状态转移与清理

进入 DIE 状态时执行全面清理（在 `_do_transition` 中）：

```gdscript
if to == State.DIE and _player != null:
    _pending_fire_side = ""                          # 清空挂起的发射
    chain_sys.hard_clear_all_chains("die")           # 立即清除所有链条（不走溶解）
    movement.move_intent = 0; velocity.x = 0         # 冻结移动
    if velocity.y < 0.0: velocity.y = 0.0            # 归零上抛速度
    health.on_player_die()                           # 清空击退残留
    player.on_die_entered()                          # Player 级兜底清理
```

### 5.4 超时保护

所有非终态动作都有超时保护，防止动画事件丢失导致永久卡死：

| 状态 | 超时时长 | 超时后行为 |
|------|:--------:|-----------|
| `ATTACK` / `ATTACK_CANCEL` | 2.0 秒 | 强制归还槽位 + resolver |
| `HURT` | 1.0 秒（stun 时动态覆盖） | 强制 resolver |
| `FUSE` | `max(3.0, fusion_lock_time + 2.0)` | 调用 `on_anim_end_fuse()` |

### 5.5 Resolver 决策逻辑

动作结束后统一调用 `_resolve_post_action_state()` 来决定下一个状态：

```gdscript
func _resolve_post_action_state() -> StringName:
    if hp <= 0:           return &"Die"
    if not on_floor:
        if vy < 0.0:     return &"Jump_up"
        else:             return &"Jump_loop"
    if intent == 2:       return &"Run"    # RUN
    if intent == 1:       return &"Walk"   # WALK
    return &"Idle"
```

Resolver 返回结果后，ActionFSM 回到 `NONE`，并同步 LocomotionFSM 到对应状态。

### 5.6 on_stunned 外部僵直

```gdscript
func on_stunned(seconds: float) -> void:
    if state == State.DIE: return
    _pending_fire_side = ""
    _hurt_timeout = seconds    # 临时覆盖 hurt 超时为僵直时长
    _do_transition(State.HURT, "stunned(%.2fs)" % seconds, 90)
```

与普通受伤的区别：不经过 Health 扣血流程，直接进入 HURT 状态，超时时长由调用方决定。

---

## 6. Health 生命系统

> 源文件：`scene/components/player_health.gd`

### 6.1 核心属性

| 属性 | 默认值 | 说明 |
|------|:------:|------|
| `max_hp` | 5 | 最大生命值 |
| `invincible_time` | 0.1s | 受击后无敌帧时长 |
| `post_hit_stun_time` | 0.2s | 击退落地后的额外僵直 |
| `knockback_air_time` | 0.25s | 击退空中飞行时间 |
| `knockback_distance` | 110.0 | 击退水平距离 |
| `knockback_arc_height` | 40.0 | 击退抛物线高度 |

### 6.2 信号

```gdscript
signal damage_applied(amount: int, source_pos: Vector2)
signal hp_changed(new_hp: int, old_hp: int)
```

- `damage_applied` 连接到 `player._on_health_damage_applied()`，进而触发 `action_fsm.on_damaged()`
- `hp_changed` 供 UI 监听

### 6.3 伤害流程

```
apply_damage(amount, source_pos)
  ├─ amount <= 0 → 忽略
  ├─ hp <= 0（已死亡）→ 忽略
  ├─ 无敌帧中 → 忽略
  └─ 正常伤害：
       ├─ hp = clamp(hp - amount, 0, max_hp)
       ├─ 启动无敌帧（_inv_t = invincible_time）
       ├─ hp > 0 → 计算击退抛物线（方向由伤害源位置决定）
       ├─ hp <= 0 → 清空击退状态（防止死亡后被"戳飞"）
       └─ 发射 damage_applied 和 hp_changed 信号
```

### 6.4 击退物理

击退采用抛物线模型，参数化设计：

```gdscript
# 水平速度 = 方向 * 距离 / 飞行时间
_kb_vel.x = dir_x * knockback_distance / fly_time
# 初始垂直速度（向上）
_kb_vel.y = -(4.0 * knockback_arc_height) / fly_time
# 重力加速度
_kb_gravity = (8.0 * knockback_arc_height) / (fly_time * fly_time)
```

击退飞行中若提前接触地面（`is_on_floor() and vy >= 0`），立即终止飞行并进入落地僵直。

---

## 7. WeaponController 武器控制器

> 源文件：`scene/components/weapon_controller.gd`

### 7.1 武器类型与切换

```gdscript
enum WeaponType { CHAIN, SWORD, KNIFE }
```

切换顺序为循环链：`CHAIN → SWORD → KNIFE → CHAIN`

### 7.2 攻击模式

```gdscript
enum AttackMode {
    OVERLAY_UPPER,      # 上半身叠加（Chain）
    OVERLAY_CONTEXT,    # 上半身叠加 + context 选择（Sword/Knife）
    FULLBODY_EXCLUSIVE  # 全身独占（重攻击/特殊武器，预留）
}
```

| 武器 | 攻击模式 | lock_anim_until_end | 动画选择逻辑 |
|------|----------|:-------------------:|-------------|
| Chain | `OVERLAY_UPPER` | true | 按 side（R/L）选择，与移动状态无关 |
| Sword | `OVERLAY_CONTEXT` | false | 按 context（ground_idle/ground_move/air）选择 |
| Knife | `OVERLAY_CONTEXT` | true | 按 context 选择，起手后锁定 |

### 7.3 武器切换副作用

切换武器（Z 键）触发以下操作：

1. 清空 `_pending_fire_side`
2. 溶解（dissolve）所有链条（包括已 LINKED 的）
3. 强制停止当前动作动画
4. ActionFSM 硬切回 NONE

---

## 8. HealingSprite 治愈精灵系统

### 8.1 基本参数

| 参数 | 默认值 | 说明 |
|------|:------:|------|
| `max_healing_sprites` | 3 | 最大持有槽位数 |
| `healing_per_sprite` | 2 | 每颗精灵恢复 HP |
| `healing_burst_light_energy` | 5.0 | 大爆炸释放的光照能量 |
| `healing_burst_invincible_time` | 0.2s | 大爆炸附带的无敌时间 |

### 8.2 单体使用（C 键）

消耗持有的第一颗精灵，恢复 `healing_per_sprite` 点 HP：

```gdscript
func use_healing_sprite() -> bool:
    for i in range(max_healing_sprites):
        var sp = _healing_slots[i]
        if sp != null and is_instance_valid(sp):
            _healing_slots[i] = null
            sp.call("consume")
            heal(healing_per_sprite)
            return true
    return false
```

### 8.3 治愈大爆炸（Q 键）

需要 **所有 3 颗精灵** 才能触发，效果包括：

1. 消耗全部精灵
2. 授予短暂无敌（`healing_burst_invincible_time`）
3. 对 `HealingBurstArea` 范围内的怪物施加僵直（`apply_healing_burst_stun`）
4. 通过 `EventBus.emit_healing_burst()` 释放全场光照能量

### 8.4 死亡时清理

进入死亡状态时自动消耗所有持有的精灵（优先调用 `consume_on_death`，fallback 到 `consume`）。

---

## 9. 输入映射总表

| 按键 | Action 名称 | 功能 | 路由目标 |
|------|-------------|------|----------|
| A / D | `move_left` / `move_right` | 左右移动 | Movement（每帧轮询） |
| Shift | — | 跑步（配合方向键） | Movement（每帧轮询） |
| W | `jump` | 跳跃 | LocomotionFSM (`on_w_pressed`) |
| 鼠标左键 / F | `chain_fire` | Chain: 发射链条; Sword/Knife: 攻击 | Chain → `_pending_chain_fire_side`; 其他 → ActionFSM (`on_m_pressed`) |
| X | `cancel_chains` | Chain: 取消链条（带动画）; 其他: 取消动作 | Chain → ChainSystem; 其他 → ActionFSM (`on_x_pressed`) |
| Z | — | 切换武器 | WeaponController (`switch_weapon`) → ActionFSM (`on_weapon_switched`) |
| Space | `fuse` | 融合（Chain 武器，双槽位 LINKED） | ActionFSM (`on_space_pressed`) → ChainSystem (`begin_fuse_cast`) |
| C | `use_healing` | 使用治愈精灵 | Player (`use_healing_sprite`) |
| Q | `healing_burst` | 治愈大爆炸 | Player (`use_healing_burst`) |

---

## 10. 统一日志格式

`log_msg()` 输出带有完整状态快照的格式化日志，便于调试：

```
[F:帧号][L:移动状态][A:动作状态] floor=是否着地 vy=垂直速度 intent=移动意图 hp=生命值 sR=右槽位 sL=左槽位 | [来源] 消息
```

示例：
```
[F:1234][L:Idle][A:None] floor=true vy=0.0 intent=None hp=5 sR=true sL=true | [INPUT] M_pressed: Chain slot=0 queued (bypass ActionFSM)
```

`debug_log` 导出变量控制日志开关，生产环境可关闭。

---

## 11. 信号连接关系

```
Health.damage_applied
  └──▶ Player._on_health_damage_applied()
         ├── _block_chain_fire_this_frame = true
         ├── _pending_chain_fire_side = ""
         └── action_fsm.on_damaged()

Health.hp_changed
  └──▶ （UI 层监听）

Animator → Player 回调转发:
  Player.on_loco_anim_end(event)
    ├── "anim_end_jump_up"   → loco_fsm.on_anim_end_jump_up()
    └── "anim_end_jump_down" → loco_fsm.on_anim_end_jump_down()

  Player.on_action_anim_end(event)
    ├── "anim_end_attack"        → action_fsm.on_anim_end_attack()
    ├── "anim_end_attack_cancel" → action_fsm.on_anim_end_attack_cancel()
    ├── "anim_end_hurt"          → action_fsm.on_anim_end_hurt()
    └── "anim_end_fuse"          → action_fsm.on_anim_end_fuse()
```

---

## 12. 节点树结构

```
Player (CharacterBody2D)
  ├── Visual/
  │     ├── SpineSprite
  │     ├── HandL
  │     ├── HandR
  │     ├── center1, center2, center3   # HealingSprite 轨道中心
  │     └── ...
  ├── Components/
  │     ├── Movement          (PlayerMovement)
  │     ├── LocomotionFSM     (PlayerLocomotionFSM)
  │     ├── ActionFSM         (PlayerActionFSM)
  │     ├── ChainSystem       (PlayerChainSystem / Stub)
  │     ├── Health            (PlayerHealth)
  │     └── WeaponController  (WeaponController)
  ├── Animator                (PlayerAnimator)
  ├── Chains/
  │     ├── ChainLine0
  │     └── ChainLine1
  └── HealingBurstArea        (Area2D)
```
