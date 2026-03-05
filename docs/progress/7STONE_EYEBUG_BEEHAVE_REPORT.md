# StoneEyeBug Beehave 行为与动画状态梳理（当前代码）

> 参照文档：`docs/SPINE_GODOT_LATEST_INTEGRATED_STANDARD.md`。

## 0) 动画命名与旧名说明
- `flip` 为旧名（deprecated）。
- 当前翻倒相关动画：
  - 入场翻倒：`nomal_to_flip`
  - 起身恢复：`flip_to_nomal`
  - 分裂逃出：`escape_split`
  - 空壳冻结：`empty_loop`

## 1) BT 主优先级
`FLIPPED > RETREATING > IN_SHELL > ATTACK > WANDER`。

## 2) 关键行为说明

### A. FLIPPED（打翻）
流程：`nomal_to_flip -> struggle_loop`，随后二选一：
1. **恢复流**：
   - 触发条件：
     - 被 `ghost_fist / chimera_ghost_hand_l / stone_mask_bird_face_bullet` 命中一次；或
     - 5 秒内未被命中自动超时。
   - 动画：`flip_to_nomal -> idle`，并**立刻**切 `RETREATING`（进入缩壳流）。
2. **分裂流（escape_split）**：
   - 触发条件：在 FLIPPED 期间，`SoftHurtbox` 被“非上述三种来源”的武器命中超过 3 次。
   - 动画：`escape_split`（播放期间不可打断）。
   - 在 `escape_spawn` 事件触发时，于 `MolluscSpawnMark` 生成 `Mollusc.tscn`。
   - 结束后切到 `EMPTY_SHELL`，播放 `empty_loop`。

### B. EMPTY_SHELL（空壳冻结）
- 只允许 `empty_loop` 循环。
- 不再参与其它攻击/交互（包含受击、链接等）。
- 仅当 `Mollusc` 的 `Act_ReturnToShell` 触发并调用壳体 `notify_shell_restored()` 时：
  - 切到 `IN_SHELL`；
  - 动画切为 `in_shell_loop`。

### C. 进入场景后 idle 阶段卡重力问题
- 已修正 `ActSEBWander._tick_idle`：idle 阶段每帧也执行重力积分与 `move_and_slide()`，并确保 `idle` 动画持续播放，避免“首次 walk 前重力/动画卡住”。

## 3) 调试器可读性
- Beehave 调试分页项名称改为 `怪物名 (BeehaveTree节点名)`，不再只有通用 `BeehaveTree` 文本，便于定位具体怪物实例。
