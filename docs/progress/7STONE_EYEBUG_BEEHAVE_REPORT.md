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


## 9) 当前版本逻辑快照（本次同步）

- FLIPPED 恢复尾流程固定为：`flip_to_normal -> idle -> RETREATING`。
- 缩壳流（`RETREATING` / `IN_SHELL`）中被三类来源命中会立刻中断并进入 `FLIPPED`。
- `EMPTY_SHELL` 下：`SoftHurtbox` / `LightReceiver` 均禁用，仅保留 `empty_loop`。
- `notify_shell_restored()` 后恢复 `IN_SHELL + in_shell_loop`，并重新启用 `LightReceiver`。
- 攻击触发窗口：每次由缩壳链路打开，`ActSEBAttack` 结束后关闭。

## 10) StoneEyeBug 依赖链编译检查清单（本轮）

> 目标：一次性排查“父子成员冲突、失效 NodePath、动作脚本强依赖”三类高频编译/运行隐患。

### 10.1 父子成员冲突（GDScript Parse Error）

- 检查项：`StoneEyeBug` 是否重复声明父类 `MonsterBase` 已有成员。
- 结果：
  - 父类 `MonsterBase` 持有 `@onready var _light_receiver`（通过 `light_receiver_path` 绑定）。
  - `StoneEyeBug` 当前脚本不再重复声明 `_light_receiver`，冲突项已清除。
- 结论：该类“同名成员导致全链路编译失败”的问题已消除。

### 10.2 NodePath / 场景节点绑定有效性

- 检查项：`StoneEyeBug.tscn` 中 `light_receiver_path` 是否正确指向 `LightReceiver`。
- 结果：
  - `StoneEyeBug` 根节点已配置：`light_receiver_path = NodePath("LightReceiver")`。
  - 场景内存在 `LightReceiver` 节点。
- 结论：`_light_receiver` 绑定路径有效，不会退回默认 `Hurtbox` 或空引用。

### 10.3 动作脚本强依赖排查（成员/接口）

- 检查项：StoneEyeBug 相关 `actions/*.gd`、`conditions/*.gd` 是否依赖已删除成员（如 die 字段）或不存在接口。
- 结果：
  - 未发现 `"_die_anim_playing"` 等非法依赖残留。
  - `Mollusc` 路径下亦无 die 字段硬依赖。
- 结论：动作与条件脚本的已知强依赖冲突项已清理。

### 10.4 资源链完整性（.tscn -> ext_resource path）

- 检查项：`scene/enemies/stone_eyebug` 下 `.tscn` 所引用 `res://` 资源是否存在。
- 结果：脚本化扫描结果 `missing 0`。
- 结论：未发现失效外部资源路径。

### 10.5 建议固化（后续）

1. 在 CI 增加“脚本加载冒烟”步骤（逐个 preload StoneEyeBug 行为脚本）以提前暴露 parse error。
2. 保持“共享组件字段在父类统一声明，子类仅通过 NodePath 配置”的约定，避免重复声明。
3. 对 BT 关键动作（flip/shell/escape）增加最小化行为回归场景，防止字段改名后动作脚本失配。

## 11) 恢复分支后的一致性核对（按“最终版本”目标）

本节用于核对“恢复分支后代码是否仍与最终规则一致”。

- 结论：当前代码实现的是**逻辑1**，即
  `flip_to_normal -> idle -> RETREATING`（恢复后立刻进入缩壳流），
  **不是**“回到 NORMAL 并停留”。
- 同时，缩壳流（`RETREATING` / `IN_SHELL`）期间若被
  `ghost_fist / chimera_ghost_hand_l / stone_mask_bird_face_bullet` 命中，
  会立刻中断缩壳并切到 `FLIPPED`，进入 `normal_to_flip`。
- `hit_shell` 为外部雷击触发，不是 BT 自主挑选：
  雷击命中后置 `is_thunder_pending` 并切 `RETREATING`，
  `ActSEBShellFlow.before_run()` 读取该标记后先播 `hit_shell` 再 `retreat_in`。
- `hit_shell_small` 已接在“壳体无效受击反馈”分支，
  且关键动画/关键状态（攻击、缩壳、翻转）中不插播，仅闪白。
- `EMPTY_SHELL` 下 `SoftHurtbox` 与 `LightReceiver` 均禁用；
  仅在 `notify_shell_restored()` 后恢复 `LightReceiver` 并切 `IN_SHELL`。
- 攻击触发窗口仍受 `attack_enabled_after_player_retreat` 约束：
  仅在玩家触发过缩壳后才可攻击，且每次攻击完成后立即关闭窗口。

> 注：历史文案中的 `nomal_to_flip / flip_to_nomal` 为旧拼写，
> 现行实现与文档均统一为 `normal_to_flip / flip_to_normal`。

## 12) `hit_shell_small` 不工作的根因与修复

### 根因

- `hit_shell_small` 之前只挂在 `apply_hit()` 的壳体反弹分支（`_reflect_from_shell`）里。
- 但锁链武器命中 StoneEyeBug 壳体走的是 `on_chain_hit()` 路径，不会进入 `apply_hit()`。
- 因此“壳体命中（无效伤害）”这类高频场景里，反馈动画根本没有被调度，表现为 `hit_shell_small` 看起来不工作。

### 修复

- 抽取统一反馈函数 `_play_hit_shell_small_feedback()`（含“关键动画不插播，仅闪白”规则）。
- `apply_hit()` 的壳体反弹路径继续复用该函数（保持原行为）。
- 在 `on_chain_hit()` 的“壳体命中且非 EMPTY_SHELL”路径补上同一反馈调用，确保锁链命中也有一致手感。

### 结果

- 无效伤害命中壳体时（包括锁链命中），现在都会尝试触发 `hit_shell_small`；
  若处于攻击/缩壳/翻转关键阶段，仍按设计只闪白不插播动画。

## 13) 本轮排查与修复（对应最新三条问题）

### 13.1 为什么“缩壳后似乎不检测/不攻击玩家”

根因是 **BT 优先级顺序冲突**：

- 之前 `Seq_InShell`（`mode=IN_SHELL`）排在 `Seq_Attack` 前面。
- `Act_ShellFlow` 在 `IN_SHELL` 阶段会持续 `RUNNING`，导致 Selector 永远先吃到 InShell 分支，`Seq_Attack` 没机会执行。

修复：

- 将 `Seq_Attack` 前移到 `Seq_InShell` 之前；
- 同时在 `CondSEBAttackReady` 增加硬门：`mode == IN_SHELL` 才允许攻击。

结果：

- 只有在缩壳态（`IN_SHELL`）才会检测并触发 `attack_stone -> attack_lick`；
- 行走/idle（`NORMAL`）不会触发攻击。

### 13.2 “只有缩壳态才会触发攻击”规则校正

- `CondSEBAttackReady` 现已显式要求 `mode == IN_SHELL`；
- `ActSEBShellFlow._start_retreat()` 统一在缩壳流启动时开启攻击窗口并设置冷却起点，保证从翻倒恢复进壳、LightFlower 光照触发进壳、普通缩壳都能在壳内进入攻击检测窗口。

### 13.3 LightFlower 光照触发 `hit_shell` 的链路修正

根因澄清：

- 设计要求是 **StoneEyeBug 与 LightFlower 光照释放建立关系**，而不是与全局 `thunder_burst` 事件建立关系。
- 之前实现把 `StoneEyeBug` 直接挂到了 `_on_thunder_burst` 响应链上，语义偏离需求。

修复：

- `StoneEyeBug._on_thunder_burst()` 改为忽略（不响应全局雷击事件）。
- 仅保留并强化 `on_light_exposure(remaining_time)` 入口；当 LightFlower 释放光照命中时，调用
  `_trigger_lightflower_shell_react()`：
  - 若当前可进入缩壳，立即置 `is_thunder_pending=true` + `mode=RETREATING`；
  - `ActSEBShellFlow.before_run()` 读到该标记后先播 `hit_shell` 再播 `retreat_in`；
  - 若已在壳内（`RETREATING / IN_SHELL`）则忽略触发，不刷新壳计时。
- 移除 StoneEyeBug 里“通过 `light_counter >= light_counter_max` 轮询触发缩壳”的路径，避免再次与全局雷击计数耦合。

结果：

- `hit_shell` 成为 **LightFlower 光照释放驱动的外部事件反应**，而非 BT 主循环主动挑选。
- StoneEyeBug 不再与全局 `thunder_burst` 事件直接耦合，符合需求边界。

## 14) LightFlower 触发后长期停留在 Act_ShellFlow(RUNNING) 的修正

### 现象

- LightFlower 成功触发后，StoneEyeBug 会进入 `Act_ShellFlow`，并长期处于 `RUNNING`，表现为缩壳流程被持续“续时”。

### 根因

- `on_light_exposure()` 会进入 `_trigger_lightflower_shell_react()`。
- 旧实现在 `mode == RETREATING / IN_SHELL` 时会刷新 `shell_last_attacked_ms`。
- 这会不断延长 `IN_SHELL` 的安全计时窗口，导致 `Act_ShellFlow` 长时间保持 `RUNNING`。

### 修复

- 调整 `_trigger_lightflower_shell_react()`：
  - 当已处于 `RETREATING / IN_SHELL` 时，LightFlower 触发直接无效返回；
  - 不再刷新 `shell_last_attacked_ms`。

### 结果

- LightFlower 在非缩壳态可正常触发 `hit_shell -> retreat_in` 进入缩壳流；
- 一旦已在缩壳态，后续 LightFlower 触发不再干扰当前壳流程（符合“缩壳状态下雷花无效”）。
