# 修改说明（2026-02-02）

本压缩包包含已修改的代码文件（不含 project.godot）。

---

## 需要手动操作

### 1. project.godot - Action名统一（在Godot编辑器中操作）

**Project → Project Settings → Input Map**

删除（如果存在）：
- `chain_fire`
- `chain_cancel`
- `use_healing_sprite`

添加/确认：
| action名 | 按键 |
|---------|------|
| `cancel_chains` | X |
| `use_healing` | C |
| `fuse` | Space |

---

## 已包含的修改

### 2. fusion_registry.gd - 修正错误注释
位置：第94-99行
```
修正前：# 飞怪(光属性) + 走怪(暗属性) → 奇美拉A
修正后：# 飞怪(光属性) + 手怪(光属性) → 石蛇奇美拉
```

### 3. .gd文件重命名（统一为snake_case）
| 旧文件名 | 新文件名 |
|---------|---------|
| EnemyHurtbox.gd | enemy_hurtbox.gd |
| HealingSprite.gd | healing_sprite.gd |
| LightReceiver.gd | light_receiver.gd |
| RopeSim2D.gd | rope_sim_2d.gd |

### 4. .tscn文件引用路径更新
已更新所有引用上述脚本的.tscn文件中的路径。

### 5. docs目录完全替换
| 文件 | 说明 |
|------|------|
| 0_ROUTER.md | 主索引（重构） |
| A_PHYSICS_LAYER_TABLE.md | 物理层表 |
| B_GAMEPLAY_RULES.md | 玩法规则（更新完成状态） |
| C_ENTITY_DIRECTORY.md | **新增**：实体目录表 |
| D_FUSION_RULES.md | **新增**：融合规则表 |
| HOWTO_ADD_ENTITY.md | 添加实体教程（更新命名规范） |

---

## 使用方法

1. 解压到你的Godot项目目录
2. 如果提示文件冲突，选择"全部覆盖"
3. 在Godot中打开项目
4. 如果出现资源找不到的错误，尝试删除`.godot/`目录后重新打开

---

## 命名规范（已统一）

| 类型 | 规范 | 示例 |
|------|------|------|
| .tscn 文件 | PascalCase | MonsterFly.tscn |
| .gd 文件 | snake_case | monster_fly.gd |
| class_name | PascalCase | MonsterFly |
| species_id | snake_case | fly_light |
| action名 | snake_case | cancel_chains |

---

## 输入映射

| 功能 | action名 | 按键 |
|------|---------|------|
| 移动左 | move_left | A |
| 移动右 | move_right | D |
| 跳跃 | jump | W |
| 发射锁链 | (无action) | 鼠标左键 |
| 取消锁链 | cancel_chains | X |
| 融合 | fuse | Space |
| 使用回血精灵 | use_healing | C |
