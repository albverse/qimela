# 11_WEAPON_ANIM_PROFILE_SPEC.md（武器姿态 / Anim Profile：整套基础动作集替换的规范）

> 目标：支持“切换武器后，Idle/Walk/Run/Jump 等 **整套基础动作集** 与 Attack 等动作集一起切换”，并保证：
> - 不引入 LocomotionFSM 状态爆炸
> - 不让 Animator 越权改物理
> - 不在项目里出现第二个“随处播放动画”的入口
> - 切换时机与打断规则可验证、可复现

---

## 0) 核心原则（AI 必须遵守）
1) **武器姿态（profile）不是状态机状态**。LocomotionFSM/ActionFSM 不新增“持刀Idle/持刀Walk”等状态；它们仍然只输出抽象状态（Idle/Walk/Run…）。
2) **profile 只影响 Animator 的映射选择**：`profile_id + locomotion_state → anim_name`，`profile_id + action_state/context → anim_name`。
3) **只有 Animator 播放动画**；profile 切换只改变 Animator 的“映射表来源”和 Spine 的“外观配置”（skin/attachment）。
4) **切换时机必须唯一真相**：立即切换或排队切换（二选一；可允许特例但必须写清）。
5) **Hurt/Die 永远优先**，profile 切换不得阻止 Hurt/Die 的清理与抢占。

---

## 1) 术语与数据结构
### 1.1 Profile（动画档案 / 姿态）
Profile = “一套完整动作集 + 一套外观配置 + 一套切换策略”

- `profile_id`：`DEFAULT` / `KATANA` / `CHAIN` …
- `visual`（外观）：
  - `skin_name`（可选）：Spine Skin 名称（如 `katana_skin`）
  - `attachments`（可选）：对指定 Slot 设置 attachment（如 `weapon_slot -> katana_01`；切回 DEFAULT 时 -> `empty`）
- `loco_set`（基础动作集）：
  - Idle/Walk/Run/JumpUp/JumpDown/Land/Turn… → Spine anim_name
- `action_set`（动作集）：
  - AttackLight/AttackHeavy/Guard/Draw/Sheath… → Spine anim_name
- `policy`（切换策略）：
  - `switch_allowed_when`：`ONLY_WHEN_ACTION_NONE` / `QUEUE_UNTIL_ACTION_END` / `FORCE_CANCEL_ACTION_THEN_SWITCH`（三选一，推荐第二种）
  - `mix_in` / `mix_out`：默认建议 0.08 / 0.10（可被 Profile 覆盖）
  - `lock_anim_until_end`：对该 profile 下的攻击动作是否锁定动画直到结束（推荐 true）

### 1.2 Profile 与 Weapon 的关系
- WeaponType（链/武士刀/匕首）描述“武器逻辑”
- Profile 描述“姿态与动作集”
- 推荐：`WeaponType.KATANA -> profile_id=KATANA`（一对一最直观）
- 允许：同一 WeaponType 下多个 profile（例如 `KATANA_DRAWN` / `KATANA_SHEATHED`），但必须用 Draw/Sheath 动作显式切换。

---

## 2) 文档写法：你要怎样描述“持刀后整套动作变化”
新增武器或新增姿态时，按下面格式写：

### 2.1 Profile 定义（必须写全）
#### PROFILE_ID: KATANA
- visuals：
  - skin_name：`katana_skin`（或留空）
  - attachments：
    - slot: `weapon_slot` -> attachment: `katana_01`
    - slot: `chain_slot`  -> attachment: `empty`（示例）
- loco_set（全部列出，禁止省略）：
  - Idle = `idle_katana`
  - Walk = `walk_katana`
  - Run  = `run_katana`
  - JumpUp   = `jump_up_katana`
  - JumpDown = `jump_down_katana`
  - Land     = `land_katana`
  - Turn     = `turn_katana`（如没有就显式写“无，使用 Idle”）
- action_set（按你需要的动作列出）：
  - AttackLight = `atk_katana_1`
  - AttackHeavy = `atk_katana_2`
  - Guard       = `guard_katana`
  - Draw        = `draw_katana`（可选但推荐）
  - Sheath      = `sheath_katana`（可选但推荐）
- policy：
  - switch_allowed_when：`QUEUE_UNTIL_ACTION_END`（推荐）
  - mix_in=0.08、mix_out=0.10
  - lock_anim_until_end=true

---

## 3) 切换策略（最容易出错，必须写死）
你必须选择一种策略作为“唯一真相”，并在实现里严格遵守。

### 策略A：ONLY_WHEN_ACTION_NONE（最简单）
- 规则：`action_state != None` 时，Z 切换直接无效（可提示）。
- 优点：实现最简单、最稳。
- 缺点：手感可能偏硬。

### 策略B：QUEUE_UNTIL_ACTION_END（推荐）
- 规则：Z 切换在动作中会写入 `pending_profile_id`，等 Action 结束（anim_completed/timeout）时切换。
- 优点：玩家输入不丢；逻辑稳定。
- 注意：必须保证 Action 结束后一定会 resolver（completed 或 timeout 兜底），否则 pending 永久卡住。

### 策略C：FORCE_CANCEL_ACTION_THEN_SWITCH（不推荐但可用）
- 规则：动作中切换会强制触发 Cancel（或 Hurt 逻辑），立即退出动作再切 profile。
- 风险：容易引入“取消动画/状态归位”错误链。
- 若使用：必须把 Cancel 的清理清单写得非常严格。

---

## 4) 与 ActionFSM/Animator 的边界（避免状态机爆炸）
### 4.1 LocomotionFSM 不变
- LocomotionFSM 仍输出抽象 locomotion_state（Idle/Walk/Run…）。
- 绝不新增“持刀Walk”这种状态名。

### 4.2 Animator 的映射升级为二维（关键）
把：
- `LOCO_ANIM[loco_state] -> anim_name`

升级为：
- `LOCO_ANIM_BY_PROFILE[profile_id][loco_state] -> anim_name`

Action 同理（如需要）：
- `ACTION_ANIM_BY_PROFILE[profile_id][action_state_or_context] -> anim_name`

最低要求：
- 如果某 profile 缺某个 loco 动画，必须提供 fallback（例如回退到 DEFAULT 或 Idle），但必须在文档写清规则，不能让 AI 自己猜。

---

## 5) Spine 外观切换（skin/attachment）规范
### 5.1 推荐优先级
1) **Attachment 切换**（最轻量）：slot 固定，attachment 随 profile 变
2) Skin 切换（较重，但可同时切多个 attachment）

### 5.2 约束
- Slot 名与 attachment 名必须在文档中逐字写出（精确匹配 Spine 资源）。
- 切回 DEFAULT 时必须显式恢复（例如 attachment=empty 或恢复 default skin）。
- 外观切换建议发生在：
  - 策略A：切换瞬间
  - 策略B：Action 结束 resolver 的同一帧（先清动作，再切外观，再播新的 loco）

---

## 6) 需要修改的代码点（路径 + 函数名：供 AI 实施）
> 下面是“实现应落在哪里”的规范，避免 AI 发明新入口。

### 6.1 `scene/components/weapon_controller.gd`
新增/扩展：
- Profile 数据结构（建议 `WeaponAnimProfile`）
- `current_profile_id`
- `pending_profile_id`（若用策略B）
- `request_switch_profile(next_id)`：处理策略A/B/C 的判定（不播动画）
- `apply_profile_visual(profile_id)`：只处理 skin/attachment（不改 velocity、不改 FSM）

### 6.2 `scene/components/player_animator.gd`
新增/扩展：
- `LOCO_ANIM_BY_PROFILE`
- （可选）`ACTION_ANIM_BY_PROFILE`
- 在 `tick()` 中，先取 `profile_id = weapon_controller.current_profile_id`，再选 loco/action 动画。
- 对 Track1 的清理保持一致（不要因 profile 切换而残留 overlay）。

### 6.3 `scene/components/player_action_fsm.gd`
- 若需要 Draw/Sheath：把它们作为 ActionFSM 状态（FULLBODY_EXCLUSIVE），并在动作完成时切 profile（通过 WeaponController）
- 若用策略B：在 Action 完成 resolver 时调用 WeaponController 应用 pending_profile

### 6.4 `scene/player.gd`
- Z 输入只负责调用 WeaponController 的 `request_switch_profile()`（不要在这里播动画）

---

## 7) 验证用例（新增 profile 必跑）
### 用例1：静止切换
- 在 Idle 下按 Z：立刻变为持刀 Idle（动画与 attachment 同步）
- 再按 Z 切回 Chain：恢复默认 Idle 与外观

### 用例2：移动切换
- Run 中按 Z：立刻切换到 `run_katana`（或按策略排队）
- 切回验证同理

### 用例3：攻击中切换（策略相关）
- 触发 AttackLight（katana）
- 动作中按 Z：
  - 策略A：无效
  - 策略B：pending 生效，动作结束后切回
  - 策略C：立刻 cancel 并切换
通过标准：
- 不出现“动作结束事件丢失”
- 不出现 track1 残影
- 不出现外观没切但动作切了/反之

### 用例4：Hurt/Die 抢占
- 持刀状态下受击：进入 Hurt，结束后仍维持 KATANA profile（除非你明确规定受击会掉刀）
- hp=0：Die 抢占后不再切 profile，不再处理 Z 输入

---

## 8) 最小建议（给你一个默认选择）
- profile 切换策略：**QUEUE_UNTIL_ACTION_END**
- Draw/Sheath：如果你要“拔刀/收刀”仪式感，做成两个 FULLBODY_EXCLUSIVE 动作，动作完成瞬间切 profile
- Chain 的 manual bypass：只保留在链条发射/取消，不要让武器姿态走 bypass
