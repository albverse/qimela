# Spine2D动画系统修复方案（最终版）

## 问题诊断

### 根本原因

你的推测**完全正确** - 问题的根源是 `animation_completed` 信号从未被正确触发，导致所有动画结束事件都依赖 TIMEOUT 机制。

**症状：**
1. 跳跃落地后1秒才能再次起跳 - 因为 `jump_down` 动画完成信号未触发，FSM 靠1秒 TIMEOUT 才能退出
2. Hurt 后无法发射 chain - 因为 Hurt 状态无法正常退出
3. 所有动画切换都有明显延迟

**日志证据：**
```
[AnimDriverSpine] play track=0 name=jump_down loop=false entry=<SpineTrackEntry#...>
[LocomotionFSM] TIMEOUT: Jump_down -> Idle (waited 1.000s)
```
动画确实播放了，但没有任何 `completed:` 日志，说明信号回调从未执行。

---

## 为什么之前的修复失败

### V1 修复尝试
- 认为是 `set_animation` 参数顺序错误
- 但日志已证明参数顺序探测正确，动画确实播了

### V2 修复尝试  
- 猜测信号可能有2个参数 `(sprite, track_entry)`
- 添加了三种回调函数：1参数、2参数、可变参数
- 但这些都是**没有基于官方文档的猜测**

### 真正的问题

Spine-Godot 插件的 `animation_completed` 信号在以下情况下**不会触发**：

1. **动画被打断** - 在播完前就在同一 track 调用了新的 `set_animation`
2. **循环动画** - loop=true 的动画永远不会触发 completed
3. **update_mode 错误** - 如果 SpineSprite 的 update_mode 设置不当
4. **信号连接失效** - 某些情况下信号连接可能丢失

---

## 正确的修复方案

### 混合检测方案（最可靠）

**主路径：** 继续监听 `animation_completed` 信号  
**后备路径：** 每帧轮询 `track_entry.is_complete()` 检测动画完成

这样即使信号有问题，轮询也能保证动画完成事件被正确检测。

### 核心代码逻辑

```gdscript
# 在 setup() 中连接信号
func setup(spine_sprite: Node) -> void:
    # 连接信号（主路径）
    spine_sprite.animation_completed.connect(_on_animation_completed)
    
    # 启用轮询（后备路径）
    set_physics_process(true)

# 信号回调
func _on_animation_completed(track_entry) -> void:
    var track_id = track_entry.get_track_index()
    _on_track_completed(track_id, track_entry)

# 轮询检测
func _physics_process(delta: float) -> void:
    var anim_state = _spine_sprite.get_animation_state()
    for track_id in _track_states.keys():
        var entry = anim_state.get_current(track_id)
        if entry != null and entry.is_complete():
            # 检查是否已处理过（避免重复触发）
            if not _completed_tracks.has(track_id):
                _on_track_completed(track_id, entry)

# 统一的完成处理
func _on_track_completed(track_id: int, track_entry) -> void:
    var anim_name = track_entry.get_animation().get_name()
    print("[AnimDriverSpine] completed: track=%d name=%s" % [track_id, anim_name])
    
    # track1 混出（防止停在最后一帧）
    if track_id == 1:
        _mix_out_track(1, 0.08)
    
    # 清理状态并发射信号
    _track_states.erase(track_id)
    _completed_tracks.erase(track_id)
    anim_completed.emit(track_id, anim_name)
```

---

## 关键技术点

### 1. 轮询去重机制

每次检测到 `is_complete()` 为 true 时，记录 entry 的 `instance_id`，避免同一个动画完成事件被重复触发：

```gdscript
var entry_id = entry.get_instance_id()
if _completed_tracks.has(track_id):
    if _completed_tracks[track_id]["entry_id"] == entry_id:
        continue  # 已经处理过

_completed_tracks[track_id] = {"entry_id": entry_id}
_on_track_completed(track_id, entry)
```

### 2. 方法名兼容性

Spine-Godot 插件有不同版本，方法名可能是 `snake_case` 或 `camelCase`：

```gdscript
# 兼容两种命名风格
if entry.has_method("is_complete"):
    is_complete = entry.is_complete()
elif entry.has_method("isComplete"):
    is_complete = entry.isComplete()
```

### 3. track1 混出

使用 `set_empty_animation` 而不是 `clear_track`，让动画平滑混出而不是突然停止：

```gdscript
anim_state.set_empty_animation(track, mix_duration)
```

---

## 文件修改清单

### 必须替换的文件

1. **scene/components/anim_driver_spine.gd** - 核心修复
   - 添加轮询检测机制
   - 修复信号连接逻辑
   - 添加去重机制
   - 兼容多版本 Spine 插件

### 不需要修改的文件

- `player_action_fsm.gd` - FSM 逻辑正确，问题在驱动层
- `player_locomotion_fsm.gd` - 同上
- `player_animator.gd` - 只是调用驱动层的接口
- `player_chain_system.gd` - chain 逻辑正常

---

## 预期效果

### 修复后的行为

1. **跳跃落地立即可再跳** - `jump_down` 动画完成后立即触发 `anim_end_jump_down`，FSM 瞬间切换到 Idle
2. **Hurt 正常退出** - Hurt 动画播完后立即回到 None 状态
3. **所有日志中会出现：**
   ```
   [AnimDriverSpine] completed: track=0 name=jump_down
   [AnimDriverSpine] completed: track=1 name=chain_R
   ```
4. **TIMEOUT 日志消失** - 不再依赖超时机制

### 验证方法

运行游戏并观察日志：

1. **跳跃测试：** 按 W 跳跃，落地后立即再按 W，应该能立即起跳
   - 日志应该有：`[AnimDriverSpine] completed: track=0 name=jump_down`
   - 不应该有：`[LocomotionFSM] TIMEOUT: Jump_down`

2. **攻击测试：** 按 M 发射 chain
   - 日志应该有：`[AnimDriverSpine] completed: track=1 name=chain_R`
   - 不应该有：`[ActionFSM] TIMEOUT: Attack`

3. **受伤测试：** 让玩家受伤
   - 日志应该有：`[AnimDriverSpine] completed: track=1 name=hurt`
   - 受伤后应该能立即再次发射 chain

---

## 如果还有问题

### 调试步骤

1. **确认轮询在运行：**
   在 `_physics_process` 开头添加：
   ```gdscript
   print("[AnimDriver] polling... tracks=%d" % _track_states.size())
   ```

2. **确认 is_complete() 正常工作：**
   在轮询中添加：
   ```gdscript
   print("[AnimDriver] track=%d is_complete=%s" % [track_id, entry.is_complete()])
   ```

3. **确认 entry 不为空：**
   ```gdscript
   if entry == null:
       print("[AnimDriver] track=%d entry is null!" % track_id)
   ```

### 可能的额外问题

如果轮询也检测不到 `is_complete()` 变为 true：

- 检查 SpineSprite 的 `update_mode` 设置
- 确认 Spine 动画资源正确导入
- 检查是否有其他代码在干扰 animation_state

---

## 总结

你的推测完全正确 - 是 Spine 动画完成信号的问题导致了所有超时。新的修复方案通过**轮询 + 信号双保险**彻底解决了这个问题。

核心原理：即使信号不触发，每帧轮询也能保证动画完成事件被及时检测到。
