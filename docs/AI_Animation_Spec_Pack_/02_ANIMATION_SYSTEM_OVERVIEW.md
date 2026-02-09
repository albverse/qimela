# 02_ANIMATION_SYSTEM_OVERVIEW.md（现有动画系统：轨道、驱动、映射）

> 本文是“读懂现状”的最短路径。新增动作时，必须按这里的结构扩展，而不是另起炉灶。

---

## 1) Animator 的轨道约定
文件：`scene/components/player_animator.gd`

- Track0（`TRACK_LOCO=0`）：Locomotion 专用（Idle/Walk/Run/Jump_*）
- Track1（`TRACK_ACTION=1`）：Action overlay 专用（Attack/Cancel/Fuse/Hurt/Die 等）

播放模式（与 `WeaponController.AttackMode` 对齐）：
- `OVERLAY_UPPER`：上半身叠加（Chain）
- `OVERLAY_CONTEXT`：上半身叠加 + context 选择（Sword/Knife）
- `FULLBODY_EXCLUSIVE`：全身独占（特殊武器/重攻击）

---

## 2) 驱动器模式
- Mock：`scene/components/anim_driver_mock.gd`（计时模拟 completed）
- Spine：`scene/components/anim_driver_spine.gd`（对 Spine runtime 封装，向外统一 `anim_completed(track, anim_name)`）

**新增动作必须保证**：
- Mock 能跑（哪怕只是用 duration 模拟），否则回归测试会变脆
- Spine 里能触发 completed（或明确该动作是 loop 且不依赖 completed）

---

## 3) 现有映射（单一来源：PlayerAnimator 常量表）
文件：`scene/components/player_animator.gd`

### 3.1 Locomotion 映射（state → anim）
- `LOCO_ANIM`：LocomotionState → anim_name  
- `LOCO_LOOP`：anim_name → loop(bool)
- `LOCO_END_MAP`：非 loop 动画结束 → LocomotionFSM 事件（例如 jump_up / jump_down）

### 3.2 Action 映射（action_state → anim）
- `ACTION_ANIM`：ActionStateName → anim_name  
- `ACTION_END_MAP`：anim_name → ActionFSM 事件名（anim_end_*）

> 规则：新增动作要么进入这些表，要么明确属于“手动链条动画特例”。不要混用。

---

## 4) WeaponController：把“武器/上下文/动画名”集中管理
文件：`scene/components/weapon_controller.gd`

- `WeaponType`：CHAIN / SWORD / KNIFE（可扩展）
- `AttackMode`：对应 Animator 的播放模式
- `anim_map`：context → anim_name（或 side → anim_name）
- `lock_anim_until_end`：
  - true：动作开始后，context 改变也不切换动画（Chain/Knife）
  - false：允许 context 变化时切换（Sword）

**新增武器/新攻击类型时**：先更新 WeaponDef，再更新 Animator 的 `ACTION_END_MAP`（确保能回到正确状态）。

---

## 5) Chain 的“手动动画特例”说明（不要扩散）
文件：`scene/components/player_animator.gd` 中的 `MANUAL_CHAIN_ANIMS` 与 `_manual_chain_anim` 标志

- 目的：链条动画由 ChainSystem 触发时，Animator tick 不应该把 track1 当成“普通 ActionFSM 动作”去清理或发结束事件。
- 结论：**只有链条**走这个特例；新动作默认不得走特例。
