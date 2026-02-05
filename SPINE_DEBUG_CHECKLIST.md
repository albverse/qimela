# Spine2D 动画不显示诊断清单

## 已修复的问题 ✅

### 1. SpineSprite 位置错误
**修复前**：
```gdscript
position = Vector2(4, 47.999996)    # 在 Visual 节点下偏移 +48（错误）
scale = Vector2(0.4841056, 0.48443115)
```

**修复后**：
```gdscript
position = Vector2(0, -42)          # 对齐原 Sprite2D 位置
scale = Vector2(0.5, 0.5)           # 统一缩放
```

### 2. 添加调试日志
在 `player_animator.gd` 中添加了完整的调试输出：
- SpineSprite 节点是否找到
- 动画播放调用是否成功
- AnimationState 方法是否存在

---

## 测试步骤（请按顺序操作）

### 第 1 步：检查控制台输出

运行游戏后，**立即查看控制台**，应该看到：

#### ✅ 正常输出（动画正常工作）：
```
[PlayerAnimator] Initializing... spine_path=../../Visual/SpineSprite
[PlayerAnimator] SpineSprite found: SpineSprite (type=SpineSprite)
[PlayerAnimator] Connected to signal: animation_completed
[PlayerAnimator] Playing initial animation: idel
[PlayerAnimator] Playing: idel (loop=true, track=0)
```

#### ❌ 异常输出 1（节点未找到）：
```
[PlayerAnimator] Initializing... spine_path=../../Visual/SpineSprite
ERROR: [PlayerAnimator] SpineSprite not found at: ../../Visual/SpineSprite
```
**原因**：场景结构与代码不匹配  
**修复**：在 Player.tscn 中检查 `Visual/SpineSprite` 节点是否存在

#### ❌ 异常输出 2（Spine 插件问题）：
```
[PlayerAnimator] SpineSprite found: SpineSprite (type=SpineSprite)
ERROR: [PlayerAnimator] SpineSprite missing get_animation_state method!
```
**原因**：Spine 插件未正确加载或版本不兼容  
**修复**：
1. 检查 `项目 → 项目设置 → 插件` 是否启用 Spine
2. 确认 Godot-Spine 插件版本与 Godot 4.5 兼容

#### ❌ 异常输出 3（动画名称错误）：
```
[PlayerAnimator] Playing: idel (loop=true, track=0)
[PlayerAnimator] Playing: idel (loop=true, track=0)  # 重复，但没有实际播放
```
**原因**：Spine 项目中动画名是 `"idle"` 而非 `"idel"`  
**修复**：
1. 在 Spine 软件中确认动画名称
2. 修改 `player_animator.gd` 中的 `anim_idle` 变量（第 15 行）

---

### 第 2 步：检查 SpineSprite 可见性

如果控制台没有错误，但仍看不到角色：

#### 方法 A：临时显示老 Sprite2D（对比）
在 `Player.tscn` 中：
```gdscript
[node name="Sprite2D" type="Sprite2D" parent="Visual"]
visible = true  # 改为 true
```
运行游戏，如果能看到老 sprite 但看不到 Spine，说明：
- Spine 位置/缩放仍有问题
- 或 Spine 资源加载失败

#### 方法 B：检查 Spine 资源
打开 `res://art/player/spine/player_spine.tres`，确认：
- Atlas 路径正确
- Skeleton 文件加载成功
- 没有红色感叹号（资源缺失）

---

### 第 3 步：动画名称对照表

**Spine 项目中的动画名称必须与代码一致**：

| 代码中的动画名（GDScript） | Spine 中必须存在的动画名 |
|---------------------------|------------------------|
| `anim_idle = "idel"`      | ⚠️ 应该是 `"idle"` |
| `anim_walk = "walk"`      | `"walk"` ✓ |
| `anim_run = "run"`        | `"run"` ✓ |
| `anim_jump_up = "jump_up"` | `"jump_up"` ✓ |
| `anim_jump_loop = "jump_loop"` | `"jump_loop"` ✓ |
| `anim_jump_down = "jump_down"` | `"jump_down"` ✓ |
| `anim_chain_R = "chain_R"` | `"chain_R"` ✓ |
| `anim_chain_L = "chain_L"` | `"chain_L"` ✓ |
| ... | ... |

⚠️ **注意**：`Player.tscn` 中 `preview_animation = "idel"`（拼写错误）

---

## 常见问题 FAQ

### Q1: 控制台没有任何 [PlayerAnimator] 输出
**原因**：`Components/Animator` 节点的脚本未挂载  
**修复**：在 Player.tscn 中检查 Animator 节点是否有脚本

### Q2: 角色完全不可见（包括碰撞框）
**原因**：Player 节点位置在屏幕外  
**修复**：在场景树选中 Player，按 F 键（Frame Selected）聚焦

### Q3: Spine 动画播放，但角色在原地不动
**原因**：
1. Spine 骨骼根节点位置不在原点
2. 或骨骼动画只包含骨骼旋转，没有位移

**检查**：在 Spine 软件中查看骨骼树，确认根骨骼位置

### Q4: 翻转后动画错位
**原因**：`facing_visual_sign` 设置错误  
**当前值**：`facing_visual_sign = 1.0`（Spine 朝右，正确）  
**如果 Spine 朝左**：改为 `-1.0`

---

## 紧急回退方案

如果 Spine 仍然无法显示，临时使用老 Sprite2D：

```gdscript
# Player.tscn
[node name="Sprite2D" type="Sprite2D" parent="Visual"]
visible = true  # 启用

[node name="SpineSprite" type="SpineSprite" parent="Visual"]
visible = false  # 禁用
```

然后在 `player_animator.gd` 的 `_ready()` 中添加：
```gdscript
if _spine == null:
    push_error("[PlayerAnimator] Fallback to static sprite (Spine disabled)")
    set_process(false)
    return
```

---

## 下一步

**测试后反馈以下信息**：
1. 控制台的完整输出（特别是 [PlayerAnimator] 开头的）
2. 是否能看到角色（即使不动）
3. 动画是否在 Spine 编辑器中能正常预览

我会根据反馈继续修复。
