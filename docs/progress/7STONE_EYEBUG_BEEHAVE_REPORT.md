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
