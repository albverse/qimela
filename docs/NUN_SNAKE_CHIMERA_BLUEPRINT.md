# 《修女蛇（临时代号）工程蓝图 v0.1》

> 目标：把现有需求整理为 **AI 可直接执行** 的工程规范（Godot 4.5 + GDScript + Beehave）。
> 说明：本蓝图严格对齐当前项目硬规则（Monster/Chimera/weak/chain/Beehave/EventBus）。
> 状态：**可落地，但含若干待你确认项**（见文末“需你确认的问题”）。

---

## 0. 名词归一（先统一再开发）

为避免 AI/程序/美术命名漂移，先做术语映射：

| 需求原词 | 工程标准名（建议） | 备注 |
|---|---|---|
| 修女蛇 | `ChimeraNunSnake`（class_name） | 场景文件建议 `scene/enemies/chimera_nun_snake/ChimeraNunSnake.tscn` |
| beehave | `Beehave` | 项目中统一拼写是 Beehave |
| ghostfist | `ghost_fist` | 与现有命名风格保持一致 |
| ChimeraGhostHandL | `chimera_ghost_hand_l` | 现有 species_id |
| eyehurtbox / eyeHurtbox | `EyeHurtbox`（节点）+ `eye_hurtbox`（变量） | 统一大小写规则 |
| 光花放电事件 | `lightning_flower_discharge`（建议事件键） | 需与你确认最终事件来源 |
| 石化 | `PETRIFIED`（玩家新状态） | 新增状态机分支 |

---

## 1. 与当前项目硬规则的对齐约束（不可违反）

1. **实体类型必须是 Chimera**：`entity_type = EntityType.CHIMERA`。
2. **但链条链接规则走 Monster 逻辑**：默认不可直接链，只有 `weak` 或 `stunned` 可链（覆盖 ChimeraBase 默认“可直链”行为）。
3. **除“可融合”外，行为按 Monster 攻击型敌人处理**：可攻击玩家、可受击、可进入 weak/stun。
4. **Beehave 条件节点无副作用，动作节点才执行行为**。
5. **新增事件必须通过 EventBus `emit_*` 封装发出**，禁止直接 `.emit()`。
6. **可调参数导出到 Inspector**（除你指定“在舞台直调更直观”的碰撞框类参数）。

---

## 2. 目标实体配置（可直接抄到实现）

```yaml
entity:
  type: CHIMERA
  class_name: ChimeraNunSnake
  species_id: chimera_nun_snake   # 待你确认
  attribute_type: DARK            # 待你确认（先建议暗）
  size_tier: MEDIUM               # 待你确认

hp_system:
  max_hp: 5
  weak_hp: 1                      # 建议默认1，可调
  vanish_fusion_required: 1       # 占位，待融合规则补充

chain_rule_override:
  direct_link_allowed: false
  link_allowed_when: [weak, stunned]

movement:
  use_gravity: true               # 若是地面型；若悬浮改false
  move_speed: 90.0
  chase_speed: 120.0
  tail_chase_speed: 150.0
```

---

## 3. 导出参数清单（推荐全部 Inspector 可调）

> 原则：移动速度、检测半径、时长、冷却、伤害、窗口时间全部参数化。

### 3.1 通用参数

- `@export var max_hp: int = 5`
- `@export var weak_hp: int = 1`
- `@export var move_speed: float = 90.0`
- `@export var detect_player_radius: float = 240.0`
- `@export var detect_attack_target_radius: float = 240.0`  
  （用于 `enemy_attack_target` 组，如被链住的 `chimera_ghost_hand_l`）

### 3.2 状态参数

- `@export var guard_break_stun_sec: float = 0.8`
- `@export var open_eye_idle_timeout: float = 1.2`
- `@export var closed_eye_poll_interval: float = 0.1`
- `@export var weak_eye_recall_check_interval: float = 1.0`

### 3.3 攻击参数

- 僵直攻击（攻击1）
  - `stiff_attack_range: float = 80.0`
  - `stiff_attack_damage: int = 1`
  - `stiff_attack_player_stun_sec: float = 0.2`
  - `stiff_attack_to_eye_shot_delay: float = 0.0`
- 发射眼球（攻击1.1）
  - `eye_projectile_speed: float = 420.0`
  - `eye_projectile_hover_sec: float = 0.5`
  - `eye_projectile_retarget_count: int = 3`
  - `eye_projectile_invincible: bool = true`
  - `eye_return_speed: float = 700.0`
- 锤地（攻击3）
  - `ground_pound_range: float = 110.0`
  - `ground_pound_damage: int = 1`
- 甩尾（攻击4）
  - `tail_sweep_range: float = 140.0`
  - `tail_sweep_knockback_px: float = 200.0`
  - `tail_sweep_execute_petrified: bool = true`

### 3.4 石化参数（玩家）

- `@export var petrify_enabled: bool = true`（测试默认 true）
- `@export var petrify_auto_recover_sec: float = 3.0`
- `@export var petrify_forced_death_sec: float = 10.0`
- `@export var petrify_hurt_kill: bool = true`

---

## 4. 状态机蓝图（修女蛇）

> 顶层状态：`CLOSED_EYE` / `OPEN_EYE` / `GUARD_BREAK` / `WEAK` / `STUN` / `DEAD`

### 4.1 CLOSED_EYE（闭眼）

- 进入时：
  - 禁用 `EyeHurtbox`。
  - 设置“免疫过滤”：仅接受下列来源触发破防：
    - `ghost_fist`
    - `chimera_ghost_hand_l`
    - 光花放电事件（最终事件名待确认）
- 受击规则：
  - chain 命中仅溶解，不建链，不扣血（像静物）。
  - 其他普通武器无效。
- 感知规则：
  - 若检测到 `player` 或 `enemy_attack_target` 中可攻击目标 → 切 `OPEN_EYE`，并随机抽攻击：`stiff_attack` / `ground_pound`。

### 4.2 GUARD_BREAK（破防，归属睁眼系）

- 播放 `guard_break` 动画。
- 期间僵直 `0.8s`，只允许被 `weak` / `stun` 覆盖。
- `EyeHurtbox` 开启可受击。
- 结束逻辑：
  - 若已进入 `weak/stun`：交由对应状态。
  - 否则立即检测玩家是否在尾扫范围：
    - 在范围内：`tail_sweep` → `close_eye_transition` → `CLOSED_EYE`
    - 不在范围：直接 `CLOSED_EYE`

### 4.3 OPEN_EYE（睁眼）

- 禁止移动（按你要求）。
- 露出眼球，`EyeHurtbox` 可受击。
- 仅 `EyeHurtbox` 被命中时减少 hp；达到阈值进入 `WEAK`。
- 睁眼期间被光花雷击可进入 `STUN`。

### 4.4 WEAK / STUN

- 沿用 MonsterBase 既有流程。
- `WEAK` 时：
  - 播放 `weak` → `weak_loop`。
  - 若眼球子弹在场，立即下达“回眼窝”命令；回归后销毁。
  - 仅允许 `weak_loop`（不再切其他攻击动画）。

---

## 5. 伤害判定矩阵（关键）

| 状态 | 链条 chain | 近战普通武器 | ghost_fist | chimera_ghost_hand_l | 光花放电 | 石面鸟子弹 |
|---|---|---|---|---|---|---|
| CLOSED_EYE | 溶解，无效 | 无效 | 触发 GUARD_BREAK | 触发 GUARD_BREAK | 触发 GUARD_BREAK | 仅可打 EyeHurtbox（闭眼时EyeHurtbox禁用=实际无效） |
| OPEN_EYE | 命中 EyeHurtbox 才掉血；非 EyeHurtbox 无效 | 同左 | 有效（若命中 EyeHurtbox） | 有效（若命中 EyeHurtbox） | 可触发 STUN | 命中 EyeHurtbox 有效 |
| GUARD_BREAK | 同 OPEN_EYE | 同 OPEN_EYE | 同 OPEN_EYE | 同 OPEN_EYE | 可 STUN | 同 OPEN_EYE |
| WEAK/STUN | 可链接（按怪物规则） | 不再普通扣血（hp_locked） | 按现有 weak/stun 规则 | 按现有 weak/stun 规则 | 保持兼容 | 保持兼容 |

---

## 6. 攻击流细化（可直接写 BT Action）

### 6.1 攻击1：僵直攻击 `stiff_attack`

- 前提：`OPEN_EYE`，玩家在 `stiff_attack_range`。
- 结果：命中玩家 `-1HP` + `0.2s` 僵直。
- 动画结束后：若修女蛇未受击 → 触发攻击1.1 发射眼球。
- 若攻击动画期间修女蛇受击：`hp-1`（仅 EyeHurtbox）→ 立刻 `tail_sweep` + 闭眼。

### 6.2 攻击1.1：发射眼球 `shoot_eye`

- 眼球是独立实例（必须独立场景，便于未来弹幕复用）。
- 出生点：`EyeHurtbox` 绑定骨骼位置。
- 行为：
  1. 快速飞向玩家当前位置 → 悬停 `0.5s`
  2. 重新锁定玩家当前位置再飞行 → 悬停 `0.5s`
  3. 重复共 `3` 次
  4. 快速回归 `EyeHurtbox`，接触即销毁
- 命中效果：玩家触碰眼球立即 `PETRIFIED`。
- 眼球飞行过程无敌（不可被任何攻击命中）。
- 施法期间修女蛇维持无眼睁眼循环 `shoot_eye_loop`，且 **EyeHurtbox 仍可被攻击**。
- 若期间修女蛇进入 `WEAK`：
  - 立刻强制眼球返航；每秒校准 EyeHurtbox 位置；回归即销毁。
  - 修女蛇只播 `weak/weak_loop`。

### 6.3 攻击3：锤地 `ground_pound`

- 你要求全程闭眼态（可作为 `CLOSED_EYE` 下的主动攻击动作）。
- 建议使用独立 `GroundPoundHitbox`（Area2D）贴地检测，而非复用主 Hurtbox。
- 目标在范围内时造成伤害。

### 6.4 攻击4：甩尾 `tail_sweep`

- 判定范围大于僵直攻击。
- 建议将 `TailSweepHitbox` 绑定尾部骨骼。
- 命中非石化玩家：至少 `200px` 击退。
- 命中石化玩家：即死，`hp=0` + 播放 `die_by_stone`。
- AI优先级补充：
  - 若场内存在石化玩家：优先追逐石化玩家 → 入范围后优先 `ground_pound`（你文中写“调用攻击流3”）。

---

## 7. 新增玩家状态：PETRIFIED（石化）

> 放入玩家 Action/FSM，行为冻结等同 DIE，但保留 hurt 输入作为 die_by_stone 触发前提。

### 7.1 状态行为

- 进入：播放 `petrify_enter`。
- 循环：`petrify_loop`。
- 退出：`petrify_exit`（仅当解药开关开且时间到）。
- 石化中禁止：移动、跳跃、武器切换、链条发射、绝大多数 action。
- 石化中允许：hurt 检测（用于触发即死 `die_by_stone`）。

### 7.2 时间与死亡规则

- `petrify_enabled = false`：永不恢复。
- `petrify_enabled = true`：`3s` 自动恢复。
- 石化状态下，若被任意怪物/任意 hurt 命中：立即 hp 清零 + `die_by_stone`。
- 石化状态累计超过 `10s`：立即 hp 清零（触发 `die_by_stone`）。

---

## 8. Beehave 行为树落地草案

```text
RootSelector
├─ Seq_DeadOrWeakStunHandling
│  ├─ Cond_IsDeadOrWeakOrStun
│  └─ Act_HandleDeadOrWeakOrStun
├─ Seq_GuardBreak
│  ├─ Cond_ModeIs(GUARD_BREAK)
│  └─ Act_GuardBreakFlow
├─ Seq_OpenEyeAttack
│  ├─ Cond_ModeIs(OPEN_EYE)
│  └─ Act_OpenEyeAttackFlow   # stiff/ground_pound随机 + eye_shoot链路
├─ Seq_ClosedWakeAndReact
│  ├─ Cond_ModeIs(CLOSED_EYE)
│  ├─ Cond_DetectTarget(player|enemy_attack_target)
│  └─ Act_OpenEyeAndSelectAttack
└─ Act_ClosedEyeIdle
```

### Blackboard 键建议

- `mode`
- `target_node`
- `last_attack_type`
- `is_eye_projectile_active`
- `is_player_petrified`
- `guard_break_end_ms`
- `petrify_enabled`

---

## 9. 动画资源组织（你特别要求）

### 9.1 文件夹建议

```text
spine_assets/chimera_nun_snake/
├─ open_eye/
│  ├─ open_eye_idle
│  ├─ open_eye_to_close
│  ├─ guard_break
│  ├─ stiff_attack
│  ├─ shoot_eye_start
│  ├─ shoot_eye_loop      # 无眼睁眼循环
│  ├─ shoot_eye_end
│  ├─ weak
│  ├─ weak_loop
│  └─ stun
└─ closed_eye/
   ├─ closed_eye_idle
   ├─ close_to_open
   ├─ ground_pound
   ├─ tail_sweep
   └─ hurt_closed         # 可选
```

### 9.2 Spine 事件建议（保证演出和逻辑对齐）

| 事件名 | 动画 | 用途 | 必要性 |
|---|---|---|---|
| `atk_hit_on` | `stiff_attack`/`ground_pound`/`tail_sweep` | 开启命中窗口 | 必须 |
| `atk_hit_off` | 同上 | 关闭命中窗口 | 必须 |
| `eye_shoot_spawn` | `shoot_eye_start` | 生成眼球实例 | 必须 |
| `eye_shoot_loop_enter` | `shoot_eye_start` | 切到 `shoot_eye_loop` | 推荐 |
| `guard_break_done` | `guard_break` | 破防阶段结束 | 必须 |
| `close_eye_done` | `open_eye_to_close` | 回到 `CLOSED_EYE` | 必须 |

### 9.3 骨骼/挂点建议

- `bone_eye_socket`：眼球发射/回收锚点（与 EyeHurtbox 对齐）
- `bone_tail_hit`：尾扫判定挂点
- `bone_ground_center`：锤地地面判定中心
- `bone_head_look`：可选，追踪玩家朝向

---

## 10. 代码结构建议（AI执行清单）

1. 新建目录：`scene/enemies/chimera_nun_snake/`
2. 新建场景：`ChimeraNunSnake.tscn`（主节点继承 `ChimeraBase` 子类脚本）。
3. 新建脚本：
   - `chimera_nun_snake.gd`
   - `bt_chimera_nun_snake.tscn`
   - `actions/*.gd`（guard_break/open_eye_attack/closed_eye_idle...）
   - `conditions/*.gd`（mode 检查、范围检查、目标存在）
4. 新建眼球子弹：`NunSnakeEyeProjectile.tscn` + `nun_snake_eye_projectile.gd`
5. 玩家侧：新增 `PETRIFIED` 状态处理与动画钩子。
6. EventBus：补齐你最终确认的“光花放电事件”接入点。
7. 融合规则：先占位（见 11 节），不写具体产物。

---

## 11. 融合规则占位（按你要求暂不实现）

```yaml
fusion_placeholder:
  enabled: true
  implemented: false
  todo:
    - register species_id in C_ENTITY_DIRECTORY.md
    - add fusion combinations in D_FUSION_RULES.md
    - define success / rejected / fail_hostile / fail_vanish behavior
```

---

## 12. 风险点与易错点（提前规避）

1. **Chimera 默认可直链** 与本需求冲突，必须在子类强制改写 `on_chain_hit()`。
2. `EyeHurtbox` 与主 `Hurtbox` 的伤害路由需彻底分离，避免非眼部误掉血。
3. 眼球子弹返航时若 EyeHurtbox 被关闭/隐藏，需 fallback 到 `bone_eye_socket` 坐标。
4. 玩家 `PETRIFIED` 若直接复用 `DIE`，容易误触发 respawn 流程，建议独立状态枚举。
5. “石化玩家优先追逐”与“睁眼禁移动”冲突：建议仅在 `tail_sweep` 逻辑分支短暂放开移动，执行后立即闭眼。

---

## 13. 需你确认的问题（请逐条回复）

1. **物种ID** 是否确定为 `chimera_nun_snake`？
2. 修女蛇的 **属性** 是暗属性吗（`DARK`）？体型是否 `MEDIUM`？
3. 你写的“光花放电事件”在现工程里具体是：
   - LightningFlower 的哪个信号/事件？
   - 还是 `healing_burst` / `thunder_burst` 之一？
4. “只有 eyehurtbox 可被石面鸟子弹伤害”是指：
   - 仅石面鸟子弹能伤到眼球？
   - 还是眼球还能被玩家 chain/武器命中（你前文说可被 chain 命中）？
5. 攻击编号里缺少“2”，你当前版本是否确认只有 **1、1.1、3、4** 四类攻击？
6. “僵直攻击动画期间被 hurt 则立刻闭眼+甩尾”中的 `hurt` 是否只指 `EyeHurtbox` 命中？
7. 石化状态下“保留 hurt 输入作为 die_by_stone 前提”：是否包含**环境伤害**与**自伤**？
8. 石化解药开关你希望挂在：
   - Player 导出参数（关卡可配）
   - 全局调试开关（Autoload）
   - 还是关卡脚本常量？
9. 你提到“修女蛇应优先移动到石化玩家位置”，是否允许它在闭眼状态也追逐？（当前文案里“睁眼禁移动”）
10. 动画命名你是否接受本蓝图建议名，还是你已有 Spine 命名清单需我改成一致？

---

## 14. 给 AI 的最小执行指令（可复制）

> 请按 `docs/NUN_SNAKE_CHIMERA_BLUEPRINT.md` 实现 `ChimeraNunSnake`，严格遵守 `docs/CONSTRAINTS.md`。先完成：
> 1) 新敌人场景+脚本+Beehave树骨架；
> 2) EyeHurtbox独立受击与闭眼免疫矩阵；
> 3) 眼球子弹独立实例（3次追踪+返航）；
> 4) 玩家 PETRIFIED 状态机与 die_by_stone 规则；
> 5) 融合规则仅占位，不实现产物。

