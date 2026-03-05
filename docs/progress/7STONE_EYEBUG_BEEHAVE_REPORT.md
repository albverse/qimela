# StoneEyeBug Beehave 行为与动画状态梳理（当前代码）

> 参照文档：`docs/SPINE_GODOT_LATEST_INTEGRATED_STANDARD.md`（叶节点统一通过 `anim_play()` 驱动，不在玩法层直连 Spine 细节）。

## 1. 行为树总结构（优先级从高到低）

`bt_stone_eyebug.tscn` 的 Root 是 `SelectorReactive`，顺序如下：

1. `Seq_Flipped`（`mode=FLIPPED`）
2. `Seq_ShellFlow`（`mode=RETREATING`）
3. `Seq_InShell`（`mode=IN_SHELL`）
4. `Seq_Attack`（玩家在检测区 + 攻击冷却到期）
5. `Act_Wander`（兜底常驻）

因此只要高优先级条件成立，低优先级行为会被打断。

---

## 2. 各行为逻辑与对应动画

### A) Flipped 分支（被打翻后）

- 入口条件：`mode == FLIPPED`。
- 第一段动作：`ActSEBFlipAndStruggle`
  - 播放 `flip`（非循环）。
  - 收到 `flip_done` 事件（或 `anim_is_finished("flip")`）后：
    - 打开软腹判定 `soft_hitbox_active=true`；
    - 切到 `struggle_loop`（循环）；
    - 返回 `SUCCESS`。
- 第二段（InnerSelector）：
  - 若 `was_attacked_while_flipped=true`：执行 `ActSEBEscapeSplit`
    - 播放 `escape_split`（非循环）；
    - `escape_spawn` 事件（或 350ms 兜底）时生成 Mollusc；
    - 动画结束后切空壳并播放 `in_shell_loop`。
  - 否则执行 `ActSEBStruggleIdle`
    - 持续播放 `struggle_loop`（循环），持续 `RUNNING` 等待被攻击触发分裂。

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

## 3. 受击逻辑与行为切换关系（简述）

- `NORMAL` 状态被 `ghost_fist / chimera_ghost_hand_l / stone_mask_bird_face_bullet` 命中会进入 `FLIPPED`（走上面的翻倒分支）。
- 雷花命中会进入 `RETREATING`（走缩壳分支）。
- `FLIPPED` 期间被打只标记 `was_attacked_while_flipped`，由 BT 切到 `escape_split`，不会在 `apply_hit` 里直接切动画。
- `EMPTY_SHELL` 受击走空壳受击反馈 `hit_shell_small`，并可进入弱化/可链接流程。

---

## 4. 本次发现并修正的明显矛盾

### 问题
`stone_eyebug.gd` 注释写着 `detect_area_radius` 要与场景 DetectArea 半径保持一致，但默认值是 `150.0`，而 `StoneEyeBug.tscn` 中 DetectArea 圆形半径是约 `129`，二者不一致。

### 修复
将 `stone_eyebug.gd` 的 `detect_area_radius` 默认值改为 `129.0`，与当前场景配置对齐，避免“文档/参数说明一致但实际数值不一致”的维护风险。
