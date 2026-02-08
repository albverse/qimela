# Spine2D集成问题分析与修复方案

## 一、现状分析

### 1. 核心问题定位

根据上次对话日志和交接文档，主要问题：

1. **`animation_completed` 信号未触发** - 这是最根本的问题
   - 动画确实播放了（日志有 `play track=X name=XXX entry=<SpineTrackEntry#...>`）
   - 但 `animation_completed` 回调永远不触发
   - 导致所有 FSM 状态转换依赖 TIMEOUT

2. **Jump_down 1秒超时** - 是症状而非根因
   - 落地后1秒内无法起跳
   - 因为 `anim_end_jump_down` 事件永远不到达
   - LocomotionFSM 只能靠 1秒 TIMEOUT 退出 Jump_down 状态

3. **Hurt后无法发射chain** - 同样是信号问题
   - Hurt 状态无法正常退出
   - 导致 ActionFSM 卡住

### 2. 当前代码的修复尝试

`anim_driver_spine.gd` 的 v2 版本尝试了:
- 自动探测 API 签名 (track,name,loop vs name,loop,track)
- 自动探测信号参数数量 (1参数 vs 2参数)
- 三种回调函数: `_on_completed_1arg`, `_on_completed_2args`, `_on_completed_variadic`

但这些都是**猜测性修复**，没有基于 Spine-Godot 官方文档。

## 二、正确的Spine-Godot信号机制

### 关键认知

Spine-Godot 4.x 官方插件的 `animation_completed` 信号需要满足以下条件才会触发：

1. **动画必须完整播放到结尾** - 如果在播完前被新动画打断，不会触发
2. **loop=false** - 循环动画不会触发 completed
3. **mix_duration 必须正确** - 如果 mix 时间设置不当，可能导致动画被提前切换

### 正确的信号签名

根据 Spine-Godot 4.x 官方文档:
```gdscript
# SpineSprite 的 animation_completed 信号签名
signal animation_completed(track_entry: SpineTrackEntry)
```

**只有1个参数** - 就是 `track_entry`，不是2个参数。

### 正确的 API 调用

```gdscript
# 获取 AnimationState
var anim_state = spine_sprite.get_animation_state()

# 设置动画 - 官方签名是 (track_index, animation_name, loop)
var track_entry = anim_state.set_animation(track_index, animation_name, loop)

# 清除轨道
anim_state.clear_track(track_index)

# 设置空动画（用于混出）
anim_state.set_empty_animation(track_index, mix_duration)
```

## 三、根本问题：为什么信号不触发

### 可能的原因

1. **update_mode 设置错误**
   - SpineSprite 的 `update_mode` 可能设置为 MANUAL
   - 导致动画不自动更新
   - 需要确保是 PROCESS 或 PHYSICS

2. **信号连接错误**
   - 可能连接到了错误的对象
   - 或者回调函数签名不匹配

3. **animation_state 生命周期问题**
   - 可能在某些情况下 animation_state 被重置
   - 导致信号连接丢失

4. **track 切换时机问题**
   - 在动画播完前调用了新的 `set_animation`
   - 打断了旧动画，completed 不触发

## 四、修复策略

### 方案A：直接使用 SpineTrackEntry.is_complete()

不依赖信号，在每帧检查动画是否完成:

```gdscript
# 在 _process 或 _physics_process 中
func _check_animation_completion():
    var anim_state = _spine_sprite.get_animation_state()
    for track_id in _tracked_animations:
        var entry = anim_state.get_current(track_id)
        if entry != null:
            if entry.is_complete():
                _on_animation_complete(track_id, entry)
```

### 方案B：修复信号连接

确保正确连接到 SpineSprite 的信号:

```gdscript
func setup(spine_sprite: Node) -> void:
    _spine_sprite = spine_sprite
    
    # 确保是 SpineSprite
    if _spine_sprite.get_class() != "SpineSprite":
        push_error("Not a SpineSprite!")
        return
    
    # 检查 update_mode
    if _spine_sprite.has_method("set_update_mode"):
        _spine_sprite.set_update_mode(SpineSprite.ANIMATION_PROCESS_PHYSICS)
    
    # 连接信号 - 只有1个参数
    if _spine_sprite.has_signal("animation_completed"):
        _spine_sprite.animation_completed.connect(_on_animation_completed)
        print("[AnimDriver] Connected animation_completed signal")
    else:
        push_error("[AnimDriver] No animation_completed signal!")

func _on_animation_completed(track_entry) -> void:
    # 处理完成事件
    pass
```

### 方案C：混合方案（推荐）

1. 正确连接信号作为主路径
2. 添加轮询检查作为后备
3. 在 timeout 前优先使用 is_complete() 检查

## 五、下一步行动

1. **创建最小测试用例**
   ```gdscript
   # 在 Player._ready() 中
   func _test_spine_signal():
       var sprite = $Visual/SpineSprite
       sprite.animation_completed.connect(_test_callback)
       var state = sprite.get_animation_state()
       state.set_animation(0, "idle", false)  # 播放一个不循环的动画
       print("Test animation started, waiting for completed signal...")
   
   func _test_callback(track_entry):
       print("SUCCESS: animation_completed triggered!")
       print("Track: %d" % track_entry.get_track_index())
       print("Animation: %s" % track_entry.get_animation().get_name())
   ```

2. **确认信号是否触发**
   - 如果触发了，问题在 AnimDriverSpine 的信号处理逻辑
   - 如果没触发，问题在 SpineSprite 的配置或 Godot-Spine 插件版本

3. **根据结果选择修复方案**
   - 信号可用 → 修复 AnimDriverSpine 的信号处理
   - 信号不可用 → 实施方案A（轮询 is_complete）

