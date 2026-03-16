# BossGhostWitch 行为与动画事件实现审计（基于蓝图 v3）

> 审计范围：`scene/enemies/boss_ghost_witch/**` 对照 `docs/progress/BOSS_GHOST_WITCH_BLUEPRINT_v3/**`。
> 结论先行：**存在明显漂移，且包含可触发运行时错误的实现问题**。

## 总体结论

- **一致性（结构层）**：行为树主干、阶段切换、绝大多数事件名在 Boss 主体上是对齐的。
- **漂移（子实例层）**：GhostBomb / GhostSummon / HellHand 等子实例从“Spine 事件驱动”退化为“纯距离+计时器逻辑”，与蓝图的事件驱动原则冲突。
- **技术错误（高优先级）**：`ActUndeadWind` 与 `GhostWraith`/`GhostElite` 的 `setup` 参数签名不一致，存在运行时参数错误风险。

## 关键发现

### 1) 高优先级技术错误：`setup()` 参数签名不一致（会报错或行为异常）

- `ActUndeadWind` 调用 `wraith.call("setup", wraith_type, player, boss.global_position)`（3参数），但 `GhostWraith.setup` 只定义 1 个 `Vector2` 参数。
- `ActUndeadWind` 调用 `elite.call("setup", player, boss)`（2参数），但 `GhostElite.setup` 只定义 1 个 `BossGhostWitch` 参数。

**判断**：这是代码级实现错误，不是设计差异。

### 2) 中高优先级漂移：子实例大量脱离 Spine 事件驱动

蓝图明确要求攻击判定应由 Spine 事件控制，不依赖纯 timer/距离轮询；但当前若干子实例采用了简化逻辑：

- `GhostBomb.gd`：无 Spine 事件，接近玩家后累计 `explode_delay` 直接伤害。
- `GhostSummon.gd`：每帧距离判伤，无 `ghost_hitbox_on/off` 事件窗。
- `HellHand.gd`：`setup()` 内直接 `_on_spine_event("capture_check")`，并未连接真实动画事件信号。

**判断**：属于“实现策略漂移”，会造成命中窗口与演出时机脱节。

### 3) 中优先级漂移：部分动作命中仍使用逻辑判定，而非事件窗

- `ActDashAttack` 使用 `_scythe_detect_area` 轮询碰撞进行命中检测。
- `ActTombstoneDrop` 在下落阶段轮询 `_ground_hitbox` 并在落地阶段按帧数强制开关 hitbox。

**判断**：并非一定错误，但与蓝图“事件驱动命中窗”原则有偏离。

### 4) 中优先级漂移：Phase 2 选择器类型有意识改动

- 蓝图 Phase 2 描述为 `SelectorReactiveComposite`。
- 实现中改为普通 `selector`（注释说明为了避免执行中技能被兄弟分支抢占）。

**判断**：这是“有注释解释的架构偏移”，属于策略改造，不算技术错误。

### 5) 对齐项（正向）

- Boss 主脚本中 Phase1/2/3 关键事件处理（如 `phase2_ready`、`phase3_ready`、各 hitbox on/off）整体齐全。
- 婴儿石像关键事件（`dash_go`、`explode_hitbox_on/off`、`realhurtbox_on/off`）已落地。
- 行为树阶段结构、冷却键机制与蓝图大框架一致。

## 综合评分（主观）

- **蓝图一致性**：6.5 / 10
- **事件驱动完整度**：5.5 / 10
- **代码健壮性**：4.5 / 10（主要被 `setup` 参数错误拉低）

## 建议修复优先级

1. **P0**：立即修正 `ActUndeadWind` 与 `GhostWraith` / `GhostElite` 的 `setup` 参数一致性。
2. **P1**：恢复 `GhostBomb`、`GhostSummon`、`HellHand` 的 Spine 事件接线与 hitbox 事件窗控制。
3. **P2**：统一 Phase 3 高速动作（dash/tombstone 等）的命中判定策略（尽量事件化）。
4. **P3**：将“与蓝图不一致但有意为之”的点（如 P2 selector 非响应式）记录进蓝图增补或 ADR，避免后续误判。
