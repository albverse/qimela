# S0 v2 修正报告

## 本次解决的问题

### 问题 1：animation_completed 信号永远不触发（根本原因）
**根因**：Spine 官方 Godot 插件的 `animation_completed` 信号签名是 `(sprite: SpineSprite, track_entry: SpineTrackEntry)` — **两个参数**。旧代码的回调只声明了一个参数 `(track_entry)`，导致 Godot 因参数不匹配而**静默跳过回调**。

**修复**：`anim_driver_spine.gd` 新增 `_detect_signal_signature()`，在 setup 时读取信号的 args 数量，自动选择 1 参数或 2 参数的回调函数连接。

### 问题 2：Hurt 状态永久卡死
**根因**：ActionFSM 对 Attack 有 2 秒 TIMEOUT 保护，但 Hurt 没有。一旦 anim_end 不触发，Hurt 永远不退出，所有后续输入被忽略。

**修复**：`player_action_fsm.gd` 新增 `_hurt_timer` + `_hurt_timeout = 1.0s`，与 Attack 超时机制并列。

### 问题 3：Chain anchor 断链
**根因**：chain system 调用 `player.anim_fsm.get_chain_anchor_position()`，但新架构下 `player.anim_fsm = null`。

**修复**：
- `player_animator.gd` 新增 `get_chain_anchor_position()` 方法（桥接到 Spine driver 骨骼坐标）
- `player_chain_system.gd` 的 `_get_hand_position()` 改为走 `player.animator.get_chain_anchor_position()`
- 同时新增 `play_chain_fire()` / `play_chain_cancel()` 占位方法（新架构动画由 ActionFSM 状态驱动，这些只是兼容桩）

## 修改文件

| 文件 | 改动 |
|------|------|
| `anim_driver_spine.gd` | 重写：信号参数数量自动探测 + 2-arg/1-arg 回调分派 |
| `player_action_fsm.gd` | Hurt 超时保护（1 秒） |
| `player_animator.gd` | 新增 get_chain_anchor_position / play_chain_fire / play_chain_cancel |
| `player_chain_system.gd` | _get_hand_position 走 animator 公开接口 |

## 验收

运行后看日志，关键是这行必须出现：
```
[AnimDriverSpine] animation_completed args(N): [...]
[AnimDriverSpine] Connected animation_completed (N-arg: ...)
```

然后跳跃落地后：
```
[AnimDriverSpine] completed: track=0 name=jump_down loop=false
[ANIM] end track=0 name=jump_down
```
不再出现 TIMEOUT。

受伤后 1 秒内恢复（即使 anim_end 不触发也有保底）。
