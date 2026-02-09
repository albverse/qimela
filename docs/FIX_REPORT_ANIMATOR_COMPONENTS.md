# Player Components & Animator 修复报告

> 日期: 2026-02-09
> 范围: scene/components/* + scene/player.gd

---

## 一、修复总览

| 优先级 | 问题描述 | 修改文件 | 状态 |
|--------|----------|----------|------|
| **P0** | `fuse_progress` FULLBODY_EXCLUSIVE 完成事件被丢弃 | `player_animator.gd`, `player_action_fsm.gd` | 已修复 |
| **P1** | Chain 输入存在三条冗余路径 | `player_action_fsm.gd`, `player_chain_system.gd` | 已修复 |
| **P1** | `animation_ended` 信号在动画替换时产生伪完成 | `anim_driver_spine.gd` | 已修复 |
| **P2** | `play_chain_cancel()` 未更新 `_cur_action_anim` | `player_animator.gd` | 已修复 |
| **P2** | `die` 动画用 OVERLAY 模式导致底层 loco 动画穿帮 | `player_animator.gd` | 已修复 |
| **P2** | `PlayerAnimFSM` 504 行死代码未删除 | 删除 `player_anim_fsm.gd` | 已修复 |
| **P3** | `_compute_context()` 在 ActionFSM 和 Animator 中重复 | `player_action_fsm.gd` | 已修复 |
| **P3** | `SpineQuickTest` 无条件运行 | `player.gd` | 已修复 |
| **P3** | `AnimDriverMock` 缺少 fuse/sword/knife 时长 | `anim_driver_mock.gd` | 已修复 |

---

## 二、P0 详细说明：FULLBODY_EXCLUSIVE 完成事件路由

### 问题根因

`PlayerAnimator` 的双轨道架构：
- Track 0 = locomotion（idle/walk/run/jump）
- Track 1 = action overlay（chain/hurt/die）

当 `fuse_progress` 以 `MODE_FULLBODY_EXCLUSIVE` 播放时，它被放在 **Track 0**（清空所有轨道后独占播放）。但 `_on_anim_completed` 的 Track 0 分支只查 `LOCO_END_MAP`：

```
LOCO_END_MAP = { &"jump_up": ..., &"jump_down": ... }
```

`fuse_progress` 不在其中，导致完成事件被静默丢弃。ActionFSM 只能靠超时兜底退出 FUSE 状态。

### 修复方案

在 `_on_anim_completed` 的 Track 0 分支顶部新增判断：

```gdscript
if _cur_action_mode == MODE_FULLBODY_EXCLUSIVE and _cur_action_anim == anim_name:
    # die 是终态，不清空不恢复
    if anim_name == &"die":
        return
    # 正常 FULLBODY 动画：走 ACTION_END_MAP 分发
    var event = ACTION_END_MAP.get(anim_name, &"")
    if event != &"":
        _player.on_action_anim_end(event)
    # 恢复状态，让下一帧 tick 重新评估 loco
    _cur_action_anim = &""
    _cur_action_mode = -1
    _cur_loco_anim = &""
    return
```

同时将 ActionFSM 的 Fuse 超时从「主退出机制」改为「纯安全兜底」（超时时间从 0.6s 延长到 3s+，并输出警告日志）。

### 修复后的 fuse_progress 流程

```
1. ActionFSM → FUSE 状态
2. Animator.tick() → 检测 action_state == "Fuse"
3. 以 FULLBODY_EXCLUSIVE 播放 fuse_progress 在 Track 0
4. Spine 动画自然播完 → _on_anim_completed(track=0, "fuse_progress")
5. P0 FIX: 检测到 FULLBODY + 匹配 → ACTION_END_MAP → "anim_end_fuse"
6. → player.on_action_anim_end("anim_end_fuse")
7. → action_fsm.on_anim_end_fuse() → commit_fuse_cast() → 正常退出
```

---

## 三、P1 详细说明：Chain 输入路径统一

### 修复前的三条路径

1. **player.gd `_unhandled_input`**（当前生效）: 直接调用 `chain_sys.fire()` + `animator.play_chain_fire()`
2. **ActionFSM `on_m_pressed()`**（残留未使用）: 完整的 Chain 选槽 / pending_fire / ATTACK 状态逻辑
3. **ChainSystem `handle_unhandled_input()`**（残留未使用）: 独立的鼠标/键盘处理

### 修复内容

- **ActionFSM `on_m_pressed()`**: 移除所有 Chain 武器专用逻辑，仅保留 Sword/Knife 路径。Chain 武器直接 `return`。
- **ChainSystem `handle_unhandled_input()`**: 标记为 `[DEPRECATED]`，内部改为空方法。
- **ChainSystem `_get_hand_position()`**: 移除对已删除的 `AnimFSM` 节点的 fallback 查找。

### 当前唯一规范路径

```
player.gd _unhandled_input
  ├─ Chain 武器 → chain_sys.fire() + animator.play_chain_fire()
  ├─ Sword/Knife → action_fsm.on_m_pressed()
  ├─ Space → action_fsm.on_space_pressed()
  └─ X → animator.play_chain_cancel() + chain_sys.force_dissolve_all_chains()
```

---

## 四、P1 详细说明：AnimDriverSpine 信号修复

### 问题

`animation_ended` 信号在 Spine 中不仅在动画自然播完时触发，也在动画被**替换/移除**时触发。当 `play()` 替换正在播放的动画时，旧动画的 `animation_ended` 会产生伪完成事件。

### 修复内容

1. **信号优先级反转**: 改为优先连接 `animation_completed`（仅在动画自然播完循环时触发），`animation_ended` 作为 fallback。
2. **动画名验证守卫**: 在信号回调中检查完成的动画是否与 `_track_states` 中追踪的动画一致，不一致则过滤。

```gdscript
var expected_anim = _track_states[track_id].get("anim", &"")
var signal_anim = _get_animation_name(track_entry)
if signal_anim != &"" and signal_anim != expected_anim:
    return  # 过滤伪信号
```

---

## 五、P2 修复说明

### `play_chain_cancel()` 状态补齐

补充了缺失的 `_cur_action_anim` 和 `_cur_action_mode` 赋值，保持与 `play_chain_fire()` 一致。

### `die` 改为 FULLBODY_EXCLUSIVE

死亡动画从 `MODE_OVERLAY_UPPER`（Track 1 叠加）改为 `MODE_FULLBODY_EXCLUSIVE`（清空所有轨道后独占 Track 0），防止底层 locomotion 动画在死亡时继续播放。

由于 die 是终态，`_on_anim_completed` 中对 FULLBODY 的处理会检测到 `anim_name == "die"` 并直接 `return`，不会触发状态恢复。

### 删除 PlayerAnimFSM

删除 `scene/components/player_anim_fsm.gd`（504 行）及其 `.uid` 文件。同时清理了 `player_chain_system.gd` 中对 `AnimFSM` 节点的 fallback 引用。

---

## 六、P3 修复说明

| 修复 | 说明 |
|------|------|
| **`_compute_context()` 去重** | 从 ActionFSM 中移除（Chain 逻辑清理后已无调用），仅保留 Animator 中的版本 |
| **SpineQuickTest 守卫** | 放在 `debug_log` 开关后，不再在每次启动时无条件运行 |
| **Mock 时长补齐** | 新增 `fuse_progress`(0.6s), `fuse_hurt`(0.35s), `sword_light_*`(0.4/0.35s), `knife_light_*`(0.35/0.3s) |

---

## 七、修改文件清单

| 文件 | 操作 |
|------|------|
| `scene/components/player_animator.gd` | 修改（P0/P2/P2） |
| `scene/components/player_action_fsm.gd` | 修改（P0/P1/P3） |
| `scene/components/anim_driver_spine.gd` | 修改（P1） |
| `scene/components/anim_driver_mock.gd` | 修改（P3） |
| `scene/components/player_chain_system.gd` | 修改（P1/P2） |
| `scene/player.gd` | 修改（P3） |
| `scene/components/player_anim_fsm.gd` | **删除**（P2） |
| `scene/components/player_anim_fsm.gd.uid` | **删除**（P2） |
| `docs/FIX_REPORT_ANIMATOR_COMPONENTS.md` | **新增**（本文档） |
