# 1 分钟快速修复（动画无法播放）

## ⚡ 问题
```
Can not find animation: 0
Cannot convert argument 2 from int to String
```

## ⚡ 原因
Inspector 中的动画名称被清空或设置成了 `0`。

## ⚡ 修复（3 步）

### 1. 打开场景
在 Godot 中：
- 双击 `res://scene/Player.tscn`
- 选中：`Player → Components → Animator`

### 2. 填写动画名称
在右侧 **Inspector 面板**，向下滚动，找到以下配置：

**必须填写的动画名称**：

| 属性 | 值 |
|------|---|
| Anim Idle | `idle` |
| Anim Walk | `walk` |
| Anim Run | `run` |
| Anim Jump Up | `jump_up` |
| Anim Jump Loop | `jump_loop` |
| Anim Jump Down | `jump_down` |
| Anim Chain R | `chain_R` |
| Anim Chain L | `chain_L` |
| Anim Chain LR | `chain_LR` |
| Anim Chain R Cancel | `chain_R_cancel` |
| Anim Chain L Cancel | `chain_L_cancel` |
| Anim Chain LR Cancel | `chain_LR_cancel` |

**重要**：
- 确保没有空白
- 确保不是 `0` 或 `<null>`
- 确保与 Spine 项目中的动画名称**完全一致**

### 3. 保存并测试
- 保存场景（Ctrl+S）
- 运行游戏（F5）
- 查看控制台应输出：
  ```
  [PlayerAnimator] Playing: idle (loop=true, track=0)
  ```

## ✅ 成功标志
- 控制台没有 "Can not find animation: 0" 错误
- 能看到角色动画（即使站立不动也算）

## ❌ 如果仍然失败
1. 检查 Spine 项目中的动画名称是否真的是 `idle`（不是 `Idle` 或 `idel`）
2. 删除 `.godot/` 文件夹，重启 Godot
3. 截图 Inspector 面板发给我

---

## 📦 新修复包
下载 `qimela_animation_fix.tar.gz`，已包含：
- ✅ 代码层面的验证逻辑（防止空值传入）
- ✅ 修正拼写错误（`idel` → `idle`）
- ✅ 更安全的 Spine API 调用

**但是**：Inspector 中的值仍需要你**手动检查和填写**。
