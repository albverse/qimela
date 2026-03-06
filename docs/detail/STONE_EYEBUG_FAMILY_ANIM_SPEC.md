# STONE_EYEBUG_FAMILY_ANIM_SPEC.md
# 石眼虫族实体动画规格表（软体虫 + 幽灵手奇美拉）

> 权威来源：本文件。美术/程序改动必须同步更新。
> 关联代码：`mollusc.gd`、`chimera_ghost_hand_l.gd`、`act_mollusc_*.gd`、`act_ghost_hand_*.gd`

---

## 1. 软体虫（Mollusc）

**species_id:** `mollusc`
**脚本:** `scene/enemies/stone_eyebug/mollusc.gd`
**BT:** `scene/enemies/stone_eyebug/bt_mollusc.tscn`
**生命终结路径:** 回壳 `queue_free()`（BT）或 FusionRegistry `queue_free()`，**无 die 动画/状态**。

---

### 1.1 动画列表

| 动画名 | loop | Mock 时长 | 触发 BT 分支 | 说明 |
|--------|------|-----------|-------------|------|
| `idle` | ✅ | 1.0 s | `Act_Idle`（兜底，玩家不在 threat_dist 内） | 待机循环，velocity=0 |
| `run` | ✅ | 0.5 s | `Act_Escape`、`Act_ReturnToShell`（移动段） | 逃跑/回壳移动循环 |
| `enter_shell` | ❌ | 0.6 s | `Act_ReturnToShell`（到达壳体后） | 回壳融合动画，结束触发 `notify_shell_restored()` + `queue_free()` |
| `attack_stone` | ❌ | 0.6 s | `Act_AttackSequence`（Phase ATTACK_STONE） | 石化吐喷攻击，命中窗口由 `atk1_hit_on/off` 控制 |
| `attack_lick` | ❌ | 0.5 s | `Act_AttackSequence`（Phase ATTACK_LICK） | 击退舔击攻击，命中窗口由 `atk2_hit_on/off` 控制 |
| `hurt` | ❌ | 0.3 s | `_do_hurt()`（受击时调用） | 受击硬直，结束后 BT 恢复 |
| `weak_stun` | ✅ | 5.0 s | `Act_WeakStun`（hp ≤ weak_hp，虚弱状态） | 虚弱眩晕循环，velocity=0，等待 `weak_stun_t` 耗尽自然恢复 |

---

### 1.2 Spine 事件表

**状态：美术尚未添加。代码已就绪（`_on_spine_event` 已连接，ev_* 标志已定义），事件加入后立即生效。Mock 模式以 `anim_is_finished()` 兜底。**

| 事件名 | 所属动画 | 建议触发帧 | 代码行为 | 必要性 |
|--------|----------|-----------|---------|--------|
| `atk1_hit_on` | `attack_stone` | 攻击动作接触目标瞬间（约 30–40% 处） | 设 `ev_atk1_hit_on=true`、`atk1_window_open=true`；BT 在此帧对范围内玩家施加**石化僵直**（`player_stone_stun` 秒） | ⭐ 必须 |
| `atk1_hit_off` | `attack_stone` | 攻击动作收回后（约 70–80% 处） | 设 `ev_atk1_hit_off=true`、`atk1_window_open=false`；BT 以此为阶段切换信号（→ `attack_lick` 或结束） | ⭐ 必须 |
| `atk2_hit_on` | `attack_lick` | 舌头/腿部接触目标瞬间（约 30–40% 处） | 设 `ev_atk2_hit_on=true`、`atk2_window_open=true`；BT 在此帧对范围内玩家施加**水平击退**（`knockback_strength` px/s） | ⭐ 必须 |
| `atk2_hit_off` | `attack_lick` | 攻击动作收回后（约 70–80% 处） | 设 `ev_atk2_hit_off=true`、`atk2_window_open=false`；BT 以此为结束信号 | ⭐ 必须 |

**Mock 兜底逻辑（Spine 事件缺失时）：**
- `atk1_hit_on/off`、`atk2_hit_on/off` 均以 `anim_is_finished()` 代替 hit_off，命中检测在动画结束点执行。

---

### 1.3 必要骨骼

| 骨骼名 | 读取方 | 用途 |
|--------|--------|------|
| `Mollusc` | `StoneEyeBug._update_soft_hurtbox_position()` | 软体虫从石眼虫逃出**之前**的软腹骨骼位置追踪，用于 `StoneEyeBug.SoftHurtbox` 的实时位置同步。**注意：此骨骼属于 StoneEyeBug 的 Spine 资产，不是 Mollusc 自身的资产。** |

**Mollusc 自身 Spine 资产无需特定骨骼追踪（Hurtbox 是静态子节点）。**

---

### 1.4 Hurtbox 配置

| 节点 | 碰撞层 | 说明 |
|------|--------|------|
| `Hurtbox`（`enemy_hurtbox.gd`） | layer=8（EnemyHurtbox） | 壳体/全身受击区，始终 monitoring |

> Mollusc 为纯软体，无壳，所以只有单一 Hurtbox，无 SoftHurtbox 区分。受击直接走 `apply_hit()`。

---

### 1.5 BT 优先级（当前结构）

```
RootSelector (SelectorReactive)
├─ Seq_SpawnEnter [Cond_SpawnEntering]   → Act_SpawnEnter    ← 生成入场：先播 enter，结束后才进入常规行为
├─ Seq_WeakStun   [Cond_IsWeak]          → Act_WeakStun      ← 虚弱/光花弱眩晕
├─ Seq_ReturnShell [Cond_SeeEmptyShell]  → Act_ReturnToShell ← 生成>10s 且 Idle>5s 后检测到空壳才回壳
├─ Seq_IdleHitEscape [Cond_IdleHitEscapeRequested] → Act_Escape ← Idle 受击后立刻反向逃跑一段（escape_dist）
├─ Seq_Attack     [Cond_PlayerInRange]   → Act_AttackSequence← 玩家在 120px 内
├─ Seq_Escape     [Cond_PlayerNear]      → Act_Escape        ← 玩家在 200px 内逃跑
└─ Act_Idle                                                   ← 兜底：玩家不在附近
```


> Idle 受击反应规则：仅当 Mollusc 处于 `Act_Idle` 时收到 `apply_hit()`，才会登记一次应激逃跑请求；
> 在 `SequenceReactive` 下该请求会保持到这段逃跑完成（`escape_remaining <= 0`）后再清除，避免“首帧触发、次帧被条件失败打断”。
> 起跑方向为“相对攻击来源反方向”，至少跑完一段 `escape_dist`。

> LightFlower 电击补充：`Mollusc.on_light_exposure()` 现改为复用 `weak_stun` 通道（`weak_stun_t = weak_stun_time`）；
> 因此时长与常规 weak_stun 一致，且动画流程统一为 `weak_stun` → `weak_stun_loop`。

> Hurt 动画补充：Idle/Escape 分支在 `is_hurt` 时不再强制覆盖为 `idle/run`，会优先保持/补播 `hurt`，避免受击无反馈。

> Idle 受击立即逃跑补充：`Act_Escape` 已加入例外，若存在 Idle 受击应激请求，不会被 `is_hurt` 的冻结分支吞掉。

> 回壳闭环补充：StoneEyeBug 进入空壳态时会加入组 `stoneeyebug_shell_empty`，Mollusc 才能稳定命中 `Cond_SeeEmptyShell -> Act_ReturnToShell`。

> 生成入场补充：Mollusc 生成后先执行 `enter` 入场动画，结束后再解锁常规行为分支。

> 回壳时机补充：Mollusc 不会在刚生成时立刻回壳；仅当“生成时长达到 `shell_return_spawn_delay`（默认 10s）”且“连续 Idle 达到 `shell_return_idle_delay`（默认 5s）”后，才开放空壳检测并进入回壳分支。

> 眩晕恢复补充：weak/光花 weak_stun 通道激活期间会屏蔽 `stunned_t` 倒计时，避免在 weak_stun 仍 RUNNING 时误触发 `_release_linked_chains()`。

### 1.6 进退两难破局（新增）

当 Mollusc 同时检测到**左右两侧都有压力源**（例如：墙+玩家、玩家+已链接奇美拉）时，进入“强制破局”流程：

1. **立即刷新攻击 CD**（`next_attack_end_ms = 0`），不等待原冷却。
2. **优先朝玩家方向移动**（玩家优先级高于链接奇美拉）。
3. 玩家进入攻击范围时，立刻执行固定连段：`attack_stone` → `attack_lick`。
4. 连段结束后继续朝当前方向前冲，直到相对玩家**越位约 50px**（`breakout_overtake_px`）。
   - 越位阶段默认**不因前方单墙立即掉头**；仅在检测到“玩家后方同向也有墙”（确认无法越位）时才允许掉头。
5. 完成越位后清除强制状态，恢复常规“检测并逃跑”流程。

说明：
- 该逻辑只在“破局状态”下强制玩家优先，避免链接奇美拉干扰导致左右抖动卡死。
- 常规模式仍遵循 Beehave 结构，不主动改写分支优先级。

---

## 2. 幽灵手奇美拉·左（ChimeraGhostHandL）

**species_id:** `chimera_ghost_hand_l`
**脚本:** `scene/chimera_ghost_hand_l.gd`
**BT:** `scene/enemies/chimera_ghost_hand_l/bt_chimera_ghost_hand_l.tscn`
**融合来源:** `mollusc + stone_eyebug_shell`
**特性:** 无重力飞行，链接时 WASD 四向操控，攻击时冻结玩家输入。

---

### 2.1 动画列表

| 动画名 | loop | Mock 时长 | 触发 BT 分支 | 说明 |
|--------|------|-----------|-------------|------|
| `idle_float` | ✅ | 1.0 s | `Act_IdleFloat`（兜底）、`Act_LinkedMove`（静止时）、`Act_ResetFlow`（appear 结束后） | 原地悬浮待机 |
| `move_float` | ✅ | 0.6 s | `Act_LinkedMove`（WASD 有输入时） | 飞行移动循环 |
| `attack` | ❌ | 0.5 s | `Act_AttackFlow`（Phase ATTACK_ANIM） | 幽灵拳出击，命中窗口由 `hit_on/off` 控制，结束由 `attack_done` 或 `anim_is_finished` 驱动 |
| `vanish` | ❌ | 0.4 s | `Act_ResetFlow`（Phase VANISH：受伤/超距触发） | 消失效果，结束后触发位置传送 |
| `appear` | ❌ | 0.4 s | `Act_ResetFlow`（Phase APPEAR：传送完成后） | 显现效果，结束后清除重置标记，播 `idle_float` |

---

### 2.2 Spine 事件表

**状态：美术尚未添加。代码已就绪（`_on_spine_event` 已连接，ev_* 标志已定义），事件加入后立即生效。Mock 模式以 `anim_is_finished()` 兜底。**

| 事件名 | 所属动画 | 建议触发帧 | 代码行为 | 必要性 |
|--------|----------|-----------|---------|--------|
| `hit_on` | `attack` | 拳头最大伸展瞬间（约 35–50% 处） | 设 `ev_hit_on=true`、`atk_hit_window_open=true`；BT 在此帧调用 `resolve_hit_on_targets()`：命中 StoneMaskBirdFaceBullet→`reflect()`，命中 StoneEyeBug→`apply_hit(chimera_ghost_hand_l)`→弹翻，命中其他→普通伤害 | ⭐ 必须 |
| `hit_off` | `attack` | 拳头开始收回后（约 60–70% 处） | 设 `atk_hit_window_open=false`（防判定残留） | 推荐 |
| `attack_done` | `attack` | 动画完全结束前（约 95% 处，或末帧） | 设 `ev_attack_done=true`；BT 以此为解冻玩家操控的信号（`Phase → UNFREEZE`） | ⭐ 必须 |

**`vanish` / `appear` 无需事件，`anim_is_finished` 已足够精确。**

**Mock 兜底逻辑（Spine 事件缺失时）：**
- `hit_on` → 以 `anim_is_finished("attack")` 代替，命中检测在动画结束点执行。
- `attack_done` → 同 `anim_is_finished("attack")`，合并到同一判断分支。

---

### 2.3 必要骨骼

**代码层无骨骼追踪。** `AttackArea`（Area2D）是静态子节点，位置由场景树固定，不依赖骨骼。

---

### 2.4 操控模式（链接状态）

| 状态 | 玩家操控 | 幽灵手控制 | 对应 BT 分支 |
|------|---------|-----------|------------|
| 未链接 | 正常 | BT 自主浮空 | `Act_IdleFloat` |
| 链接·静止 | 冻结（`set_external_control_frozen(true)`） | WASD 四向飞行（velocity=MOVE_SPEED=200px/s） | `Act_LinkedMove` |
| 链接·有攻击请求 | 冻结 | 停止移动，出拳 | `Act_AttackFlow` |
| 攻击完成 / 断链 | 解冻 | 恢复自主 | `interrupt()` 自动解冻 |
| 受伤 / 超距重置 | 解冻（`interrupt()` 保证） | `vanish→传送→appear` | `Act_ResetFlow` |

**输入映射（链接操控）：**

| 按键 | Action | 效果 |
|------|--------|------|
| A | `move_left` | 幽灵手向左 |
| D | `move_right` | 幽灵手向右 |
| W | `jump` | 幽灵手上升（`get_axis(jump, move_down)` 返回 -1） |
| S | `move_down` | 幽灵手下降（`get_axis(jump, move_down)` 返回 +1） |

> `move_down` 已在 `project.godot` 注册（physical_keycode=83 / S键）。

---

### 2.5 BT 优先级（当前结构）

```
RootSelector (SelectorReactive)
├─ Seq_Reset    [Cond_ResetNeeded]       → Act_ResetFlow    ← 最高：受伤/超距→vanish/appear
├─ Seq_Attack   [Cond_AttackRequested]   → Act_AttackFlow   ← 攻击请求（玩家输入层写入）
├─ Seq_Linked   [Cond_IsLinked]          → Act_LinkedMove   ← 链接时 WASD 四向操控
└─ Act_IdleFloat                                             ← 兜底：原地悬浮
```

---

## 3. 代码 ↔ 资产同步清单

每次美术在 Spine 中增加/修改事件或骨骼时，必须对照以下检查项：

### Mollusc 事件同步

| 变更 | 需要同步的代码 |
|------|--------------|
| 新增 `atk1_hit_on` | 无需改代码，`mollusc.gd::_on_spine_event` 已处理 |
| 新增 `atk1_hit_off` | 同上 |
| 新增 `atk2_hit_on` | 同上 |
| 新增 `atk2_hit_off` | 同上 |
| 改动 `attack_stone` 动画名 | `act_mollusc_attack.gd` 中所有 `&"attack_stone"` 引用、`_setup_mock_durations` 键名 |
| 改动 `attack_lick` 动画名 | `act_mollusc_attack.gd` 中所有 `&"attack_lick"` 引用、`_setup_mock_durations` 键名 |
| 新增 `weak_stun` 动画 | `_setup_mock_durations` 已有占位，无需改代码 |

### ChimeraGhostHandL 事件同步

| 变更 | 需要同步的代码 |
|------|--------------|
| 新增 `hit_on` | 无需改代码，`chimera_ghost_hand_l.gd::_on_spine_event` 已处理 |
| 新增 `hit_off` | 同上（直接设 `atk_hit_window_open=false`） |
| 新增 `attack_done` | 同上 |
| 改动 `attack` 动画名 | `act_ghost_hand_attack.gd` 中 `&"attack"` 引用、mock 时长键名 |
| 改动 `vanish`/`appear` 动画名 | `act_ghost_hand_reset_flow.gd` 对应字符串 |

---

*最后更新: 2026-03-04*
