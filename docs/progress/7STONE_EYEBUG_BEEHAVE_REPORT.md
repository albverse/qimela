# StoneEyeBug Beehave 行为与动画状态梳理（当前代码）

> 参照文档：`docs/SPINE_GODOT_LATEST_INTEGRATED_STANDARD.md`（叶节点统一通过 `anim_play()` 驱动，不在玩法层直连 Spine 细节）。

## 0) 动画命名更新说明

- `flip` 为**旧名（deprecated）**，当前已改为：
  - 入场翻倒：`nomal_to_flip`
  - 起身恢复：`flip_to_nomal`
- 本文以下描述均使用新动画名。

## 1) 行为树总结构（优先级从高到低）

`bt_stone_eyebug.tscn` 的 Root 是 `SelectorReactive`，顺序如下：

1. `Seq_Flipped`（`mode=FLIPPED`）
2. `Seq_ShellFlow`（`mode=RETREATING`）
3. `Seq_InShell`（`mode=IN_SHELL`）
4. `Seq_Attack`（玩家在检测区 + 攻击冷却到期）
5. `Act_Wander`（兜底常驻）

因此只要高优先级条件成立，低优先级行为会被打断。

---

## 2) 各行为逻辑与对应动画

### A) Flipped 分支（被打翻后）

- 入口条件：`mode == FLIPPED`。
- 动作：`ActSEBFlipAndStruggle`（单动作内完成整个翻倒周期）。
- 动画流程：
  1. `nomal_to_flip`（非循环，入场翻倒）；
  2. `struggle_loop`（循环，倒地挣扎）；
  3. 满足恢复条件后播放 `flip_to_nomal`（非循环，起身恢复）；
  4. 结束后先回 `idle`（循环），随后立刻切到 `mode=RETREATING` 进入缩壳流程。
- 恢复触发条件（任一满足）：
  - FLIPPED 期间被攻击一次（只触发一次恢复请求，不会反复触发）；
  - FLIPPED 持续 5 秒仍未被攻击（自动恢复）。

> 旧流程“被攻击后 `escape_split` 分裂”已从 StoneEyeBug 的当前 BT 主路径移除。

### B) ShellFlow 分支（缩壳流程）

- 入口条件：`mode == RETREATING`。
- 动作：`ActSEBShellFlow`。
- 阶段动画：
  - 雷花触发时先播 `hit_shell`（非循环）；
  - 然后播 `retreat_in`（非循环）；
  - 完成后进入壳内播 `in_shell_loop`（循环）；
  - 安全时间结束播 `emerge_out`（非循环）；
  - 结束切回 `mode=NORMAL`。

### C) InShell 分支（壳内待机）

- 入口条件：`mode == IN_SHELL`。
- 复用动作：`ActSEBShellFlow`（同一个脚本处理 InShell 到出壳）。
- 动画主状态：`in_shell_loop`（循环），直到满足出壳条件后转 `emerge_out`。

### D) Attack 分支（对玩家攻击）

- 入口条件：
  - `CondSEBPlayerInDetect` 成功（玩家在 DetectArea 内）；
  - `CondSEBAttackReady` 成功（必须先触发过 retreat_in 许可，且 `attack_cd` 冷却完成）。
- 动作：`ActSEBAttack`。
- 阶段动画：
  1. `attack_stone`（非循环）
     - `atk1_hit_on/off` 控制石化命中窗；无事件时用动画结束兜底。
  2. 若玩家仍在检测区，再播 `attack_lick`（非循环）
     - `atk2_hit_on/off` 控制击退命中窗；无事件时同样用动画结束兜底。
  3. 完成后写入 `next_attack_end_ms`，等待下一次冷却。

### E) Wander 兜底分支（普通巡走）

- 入口：上述所有高优先级分支都不成立时。
- 动作：`ActSEBWander`（永远 `RUNNING`）。
- 动画循环：
  - `idle`（循环）↔ 三种 walk（循环）随机切换：
    - `walk_lick`
    - `walk_backfloat`
    - `walk_wriggle`
- 特殊：若 `mode == EMPTY_SHELL`，保持静止并播放 `in_shell_loop`（循环）；若正在播放 `hit_shell_small` 则不强切。

---

## 3) 受击逻辑与行为切换关系（简述）

- `NORMAL` 状态被 `ghost_fist / chimera_ghost_hand_l / stone_mask_bird_face_bullet` 命中会进入 `FLIPPED`（走翻倒分支）。
- 雷花命中会进入 `RETREATING`（走缩壳分支）。
- `FLIPPED` 期间：被攻击不会再走分裂流，只触发一次“恢复请求”；若一直没被攻击，5 秒自动恢复。
- `EMPTY_SHELL` 受击走空壳受击反馈 `hit_shell_small`，并可进入弱化/可链接流程。

---

## 4) 本次发现并修正的明显矛盾

1. **动画名已更新但旧名仍残留风险**：已将 Flipped 主流程改为使用 `nomal_to_flip` / `flip_to_nomal`，并在代码注释中标注 `flip` 为旧名。
2. **Flipped 反复触发问题**：已改为“单次触发恢复 + 5s 超时自动恢复”，避免在打翻状态下被持续攻击导致重复触发流程。
