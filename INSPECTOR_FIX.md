# 动画名称配置修复指南（紧急）

## 🔴 问题原因

错误信息：
```
Can not find animation: 0
Cannot convert argument 2 from int to String
```

**根本原因**：在 Godot Inspector 中，`Animator` 节点的动画名称变量被**清空或设置成了无效值**（如 `0`、空白等）。

---

## ✅ 立即修复步骤（5 分钟）

### 步骤 1：打开场景

在 Godot 中：
1. 双击打开 `res://scene/Player.tscn`
2. 在场景树中选中：`Player → Components → Animator`

### 步骤 2：检查 Inspector 配置

在右侧 **Inspector 面板**，向下滚动，找到以下分组：

#### ✅ 基础动画（必须填写）

| 属性名 | 应该填写的值 | 当前值（检查！） |
|--------|-------------|-----------------|
| `Anim Idle` | `idle` | ⚠️ 如果是空白或 `0`，填写 `idle` |
| `Anim Walk` | `walk` | 填写 `walk` |
| `Anim Run` | `run` | 填写 `run` |

#### ✅ 跳跃动画（必须填写）

| 属性名 | 应该填写的值 |
|--------|-------------|
| `Anim Jump Up` | `jump_up` |
| `Anim Jump Loop` | `jump_loop` |
| `Anim Jump Down` | `jump_down` |

#### ✅ 锁链动画 - 发射（必须填写）

| 属性名 | 应该填写的值 |
|--------|-------------|
| `Anim Chain R` | `chain_R` |
| `Anim Chain L` | `chain_L` |
| `Anim Chain LR` | `chain_LR` |

#### ✅ 锁链动画 - 取消（必须填写）

| 属性名 | 应该填写的值 |
|--------|-------------|
| `Anim Chain R Cancel` | `chain_R_cancel` |
| `Anim Chain L Cancel` | `chain_L_cancel` |
| `Anim Chain LR Cancel` | `chain_LR_cancel` |

### 步骤 3：保存并测试

1. **保存场景**（Ctrl+S 或 Cmd+S）
2. **运行游戏**（F5）
3. **查看控制台**，应该看到：
   ```
   [PlayerAnimator] Playing: idle (loop=true, track=0)
   ```

---

## 🖼️ Inspector 示例截图（参考）

**正确的配置应该看起来像这样**：

```
┌─ Animator (Node) ──────────────────┐
│ 脚本: player_animator.gd           │
│                                     │
│ ▼ 基础动画                          │
│   Anim Idle:     idle         ✓   │ ← 必须填写
│   Anim Walk:     walk         ✓   │
│   Anim Run:      run          ✓   │
│                                     │
│ ▼ 跳跃动画                          │
│   Anim Jump Up:   jump_up     ✓   │
│   Anim Jump Loop: jump_loop   ✓   │
│   Anim Jump Down: jump_down   ✓   │
│                                     │
│ ▼ 锁链动画 - 发射                   │
│   Anim Chain R:   chain_R     ✓   │
│   Anim Chain L:   chain_L     ✓   │
│   Anim Chain LR:  chain_LR    ✓   │
│                                     │
│ ▼ 锁链动画 - 取消                   │
│   ...（同样模式）                   │
└─────────────────────────────────────┘
```

**错误的配置（会导致报错）**：

```
┌─ Animator (Node) ──────────────────┐
│ ▼ 基础动画                          │
│   Anim Idle:     [空白]       ✗   │ ← 错误！
│   或者                              │
│   Anim Idle:     0            ✗   │ ← 错误！
│   或者                              │
│   Anim Idle:     <null>       ✗   │ ← 错误！
└─────────────────────────────────────┘
```

---

## ⚠️ 常见错误

### 错误 1：Inspector 中看不到这些属性

**原因**：
- `Animator` 节点没有挂载脚本
- 或脚本路径错误

**修复**：
1. 选中 `Animator` 节点
2. 在 Inspector 顶部，检查 `脚本` 属性
3. 应该显示：`res://scene/components/player_animator.gd`
4. 如果显示 `<空>`：
   - 点击脚本旁边的 `📁` 图标
   - 选择 `res://scene/components/player_animator.gd`

### 错误 2：填写后仍然报错

**可能原因**：
1. **动画名称与 Spine 项目不匹配**
   - 在 Spine 软件中确认动画名称
   - 确保大小写完全一致（`idle` ≠ `Idle`）

2. **Godot 缓存问题**
   - 关闭 Godot
   - 删除项目根目录的 `.godot/` 文件夹
   - 重新打开项目

3. **场景未保存**
   - 确认 Inspector 修改后按了 Ctrl+S

### 错误 3：不知道 Spine 项目中的动画名称

**查看方法 A**：在 Godot 中
1. 在文件系统面板，找到 `res://art/player/spine/player_spine.tres`
2. 双击打开（或在 Inspector 中查看）
3. 查看 `Animations` 列表

**查看方法 B**：在 Spine 软件中
1. 打开你的 Spine 项目文件（`.spine` 文件）
2. 在 `Animations` 面板查看所有动画名称
3. 复制正确的名称到 Godot Inspector

---

## 🎯 快速验证清单

完成修复后，检查以下项：

- [ ] Inspector 中所有动画名称都**不为空**
- [ ] 所有动画名称都是**小写字母**开头（如 `idle` 不是 `Idle`）
- [ ] 动画名称与 Spine 项目中**完全一致**（包括大小写、下划线等）
- [ ] 场景已保存（文件名旁没有 `*` 标记）
- [ ] 运行游戏后控制台输出：
  ```
  [PlayerAnimator] Playing: idle (loop=true, track=0)
  ```
  而不是：
  ```
  Can not find animation: 0
  ```

---

## 🆘 如果仍然失败

提供以下信息：

1. **Inspector 截图**：
   - 选中 `Animator` 节点
   - 截图整个 Inspector 面板
   
2. **Spine 动画列表**：
   - 打开 `player_spine.tres`
   - 查看 `Animations` 属性
   - 复制所有动画名称

3. **控制台完整输出**：
   - 运行游戏
   - 复制所有 `[PlayerAnimator]` 开头的日志
   - 包括所有错误信息

---

## 📌 为什么会出现这个问题？

### 场景 A：你在 Inspector 中"清空"了变量
在 Godot 4.x 中，如果你在 Inspector 中：
1. 选中文本
2. 按 Delete 或 Backspace
3. 然后切换到其他节点

变量可能被设置成空值或默认值（0）。

### 场景 B：从旧版本升级
如果你从没有 `player_animator.gd` 的旧版本升级：
- Inspector 中的 `@export` 变量会被初始化为空
- 需要手动填写

### 场景 C：脚本重新编译
如果你修改了脚本中的 `@export` 定义：
- Godot 可能清空了 Inspector 中的旧值
- 需要重新填写

---

## ✅ 预防措施（未来避免此问题）

1. **不要在 Inspector 中清空动画名称变量**
   - 如果要改名，先填新名称再删旧的

2. **备份场景文件**
   - 修改前先 `文件 → 另存为` 备份

3. **使用版本控制**
   - Git 可以回滚意外修改

4. **测试脚本**
   - 新版本代码已添加验证逻辑
   - 空值会立即报错并提示检查 Inspector
