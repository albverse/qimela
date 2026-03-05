# StoneEyeBug Beehave 行为与动画状态梳理（当前代码）

> 参照文档：`docs/SPINE_GODOT_LATEST_INTEGRATED_STANDARD.md`。

## 0) 动画命名与旧名说明
- `flip` 为旧名（deprecated）。
- 当前翻倒相关动画：
  - 入场翻倒：`normal_to_flip`
  - 起身恢复：`flip_to_normal`
  - 分裂逃出：`escape_split`
  - 空壳冻结：`empty_loop`

## 1) BT 主优先级
`FLIPPED > RETREATING > IN_SHELL > ATTACK > WANDER`。

## 2) 关键行为说明

### A. FLIPPED（打翻）
流程：`normal_to_flip -> struggle_loop`，随后二选一：
1. **恢复流**：
   - 触发条件：
     - 被 `ghost_fist / chimera_ghost_hand_l / stone_mask_bird_face_bullet` 命中一次；或
     - 5 秒内未被命中自动超时。
   - 动画：`flip_to_normal -> idle`，随后立刻切 `RETREATING` 进入缩壳流。
2. **分裂流（escape_split）**：
   - 触发条件：在 FLIPPED 期间，`SoftHurtbox` 被“非上述三种来源”的武器命中超过 3 次。
   - 动画：`escape_split`（播放期间不可打断）。
   - 在 `escape_spawn` 事件触发时，于 `MolluscSpawnMark` 生成 `Mollusc.tscn`。
   - 结束后切到 `EMPTY_SHELL`，播放 `empty_loop`。

### B. EMPTY_SHELL（空壳冻结）
- 只允许 `empty_loop` 循环。
- 不再参与其它攻击/交互（包含受击、链接等）。
- **禁用 `SoftHurtbox` 与 `LightReceiver`**，防止空壳继续受光照影响攻击链路。
- 仅当 `Mollusc` 的 `Act_ReturnToShell` 触发并调用壳体 `notify_shell_restored()` 时：
  - 切到 `IN_SHELL`；
  - 重新启用 `LightReceiver`；
  - 动画切为 `in_shell_loop`。

### C. 进入场景后 idle 阶段卡重力问题
- 已修正 `ActSEBWander._tick_idle`：idle 阶段每帧也执行重力积分与 `move_and_slide()`，并确保 `idle` 动画持续播放，避免“首次 walk 前重力/动画卡住”。

## 3) 调试器可读性
- Beehave 调试分页项名称改为 `怪物名 (BeehaveTree节点名)`，不再只有通用 `BeehaveTree` 文本，便于定位具体怪物实例。


## 4) Mollusc（软体虫）当前约束与行为补充

- **无 die 行为**：Mollusc 不应访问或依赖任何 `_die_*` 状态；当前生命终结路径仅为：
  1) 回壳（`Act_ReturnToShell` 后 `notify_shell_restored()` + `queue_free()`），
  2) 融合系统回收。
- `ActMolluscAttack` 当前攻击序列仅受 `is_hurt` 打断，不再检查不存在的 die 字段。
- 动画行为：
  - 攻击：`attack_stone -> attack_lick`；
  - 受击：`hurt`（短硬直）；
  - 逃跑/回壳移动：`run`；
  - 待机：`idle`；
  - 回壳完成：`enter_shell`。

## 5) 本轮修复结论（对应线上报错）

- 报错 `Invalid access ... _die_anim_playing` 的根因是 `ActMolluscAttack` 误读了 Mollusc 不存在的 die 字段。
- 已删除该错误依赖，保持“项目仅 weak / fuse 泯灭，无 die 逻辑”的一致性。


## 6) 攻击触发窗口约束

- StoneEyeBug 攻击只在“已进入过缩壳流程后解锁”的窗口内触发。
- 每次 `ActSEBAttack` 结束会关闭 `attack_enabled_after_player_retreat`，因此不会在普通移动状态下持续反复触发攻击。
- 下一次攻击需要再次由缩壳触发链路（如 soft 命中触发 retreat）重新解锁。


## 7) 缩壳态被三类来源命中的翻倒规则

- 在 `RETREATING` / `IN_SHELL` 状态下，若命中来源为
  `ghost_fist / chimera_ghost_hand_l / stone_mask_bird_face_bullet`，
  StoneEyeBug 会立刻进入 `FLIPPED`，不再保持缩壳无敌。
- 该规则与 `NORMAL` 态的翻倒来源保持一致。
- 即使处于缩壳流过程中（`RETREATING` / `IN_SHELL`），被三类来源命中也会立刻中断缩壳并进入 `FLIPPED`（`normal_to_flip`）。


## 8) hit_shell / hit_shell_small 规则

- `hit_shell`：雷击受击反应，不由 BT 主循环主动选择；由外部雷击事件触发后立即进入缩壳流：`hit_shell -> retreat_in`。
- `hit_shell_small`：壳体无效受击短反馈。
  - 触发：壳（Hurtbox）被无效伤害命中。
  - 限制：若正在攻击/缩壳/翻转等关键动画，不插播，仅闪白。
