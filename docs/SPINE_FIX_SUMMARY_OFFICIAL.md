# Spine 驱动器修正总结（基于官方最新标准）

## 修正的问题

### 1. 签名探测方法错误
- **旧方法**：按参数名猜测（`args[i].name`）
- **问题**：参数名可能为空或不规范
- **新方法**：按参数类型探测（`args[i].type == TYPE_INT/TYPE_STRING`）

### 2. 错误的主信号
- **旧方法**：使用 `animation_completed`
- **问题**：completed 对 loop 动画会周期性触发，不代表"真正结束"
- **新方法**：优先使用 `animation_ended`（更接近真正结束语义）

### 3. 轮询机制持有 TE 对象
- **旧方法**：`_track_states` 中存储 `entry` 对象
- **问题**：TrackEntry 不应长期持有
- **新方法**：只记录 `instance_id` 用于去重

### 4. 骨骼坐标获取方式落后
- **旧方法**：只用 `world_x/world_y` + 手动翻转 Y
- **问题**：容易出错，且忽略了官方推荐接口
- **新方法**：优先使用 `get_global_bone_transform()`（Godot 空间，无需翻转）

### 5. 默认签名假设错误
- **旧方法**：探测失败时默认签名1 `(track, name, loop)`
- **问题**：与官方实际签名相反
- **新方法**：默认签名2 `(name, loop, track)` - 官方标准

## 关键代码变化

```gdscript
// 签名探测
- var first_name: String = args[0].name.to_lower()
+ var t0: int = int(args[0].get("type", -1))
+ if t0 == TYPE_STRING and t2 == TYPE_INT: _api_signature = 2

// 信号连接
- _spine_sprite.animation_completed.connect(...)
+ _spine_sprite.animation_ended.connect(...)

// 状态存储
- _track_states[track] = {anim, loop, mode, entry}
+ _track_states[track] = {anim, loop}  # 不存 entry

// 骨骼坐标
+ if _spine_sprite.has_method("get_global_bone_transform"):
+     return _spine_sprite.get_global_bone_transform(bone_name).origin
```

## 文件替换说明

替换：`scene/components/anim_driver_spine.gd`

无需修改其他文件。
