# 0_ROUTER.md（入口/路由文档，2026-01-27）

> **使用方式（最省 token）**：默认只输入本文件。  
> 只有当本文件的"触发器"命中时，才去读对应模块文档（B/C/D/E）。  
> 目的：避免模型为了自洽把工程"全巡检"，导致输出暴涨或卡住。

---

## 1) 输出契约（必须遵守）
- 默认只输出：**步骤 + 关键代码片段**（必须标注：脚本路径 + 函数名 + 可定位的注释关键词）。
- 只有当用户明确说"给我完整文件/给我可下载工程"时，才允许输出整段脚本或打包。
- 每次只处理**一个核心任务**；若出现矛盾，先列"矛盾点 → 当前选择 → 如何验证"。

---

## 2) 当前真实待办（只保留未完成）
1. 测试所有融合规则和UI预测图标
2. 完善奇美拉行为脚本（进化/能力系统）
3. Boss战机制设计

> **已完成 (2026-01-27)**：
> - ✅ 实体类系统 (EntityBase/MonsterBase/ChimeraBase)
> - ✅ 融合注册系统 (FusionRegistry)
> - ✅ UI动画串行播放修复 (倒放→burn→cooldown)
> - ✅ 闪白系统修复
> - ✅ 锁链断开恢复Hurtbox碰撞层
> - ✅ 奇美拉断链后再次链接跟随修复
> - ✅ 新怪物创建 (Neutral/WalkB/FlyB/Hostile)

---

## 3) 最危险歧义（硬规则：不遵守就会把模型喂炸）
### Layer/Mask 的写法
- **禁止**写："Layer=5 / Mask=5"（会被误读成 bitmask=5）。
- **必须**写成："bitmask 数值 + 注释（层名(层号) / Inspector 第N层）"
  - 示例：`collision_layer = 16  # ObjectSense(5) / Inspector 第5层`

换算公式（写死在这里，避免模型自推）：  
**第N层 → bitmask = 1 << (N-1)**（例：第5层 → 16）

### Dictionary访问
- **禁止**：`result.error`
- **必须**：`result.get("error", "")`

---

## 4) 文档读取协议（Router → Modules）
默认只允许使用本文件的信息回答。  
当且仅当需要更细节时，才允许请求读取其它文档。

### 请求格式（固定一行）
`NEED_DOC: B|C|D|E | 目的: <一句话> | 关键词: <最多3个>`

- B：A_PHYSICS_LAYER_TABLE.md（碰撞层/bitmask/射线/Area2D）
- C：B_GAMEPLAY_RULES.md（玩法规则：雷花/光照/锁链规则）
- D：ERRORS_INDEX.md（仅报错时检索；只取命中条目，不读整份）
- E：PROJECT_OVERVIEW.md（项目总览/系统设计/更新记录）

---

## 5) 触发器（命中才读）
### 触发 B（Physics）
出现任一关键词：  
`collision_layer` / `collision_mask` / `layer` / `mask` / `bitmask` / `RayCast` / `Area2D` / `get_overlapping_areas` / `is_on_wall`

### 触发 C（Gameplay）
出现任一关键词：  
`雷花` / `光照` / `LightReceiver` / `MonsterFly` / `潜行` / `显形` / `thunder_burst` / `chain_interact` / `weak` / `stun`

### 触发 D（Errors）
出现 Godot 报错原文（如 `E 0:00:`、`Invalid call`、`Parser Error`、`Nonexistent function` 等）。

### 触发 E（Overview）
出现任一关键词：
`融合` / `Fusion` / `EntityBase` / `MonsterBase` / `ChimeraBase` / `系统设计` / `UI动画`

---

## 6) 工程事实（只放最短"定位信息"）
- 主场景：`res://scene/MainTest.tscn`
- 常用脚本：
  - `res://scene/entity_base.gd` (实体基类)
  - `res://scene/monster_base.gd` (怪物基类)
  - `res://scene/chimera_base.gd` (奇美拉基类)
  - `res://scene/components/player_chain_system.gd` (锁链系统)
  - `res://ui/chain_slots_ui.gd` (锁链槽位UI)
  - `res://autoload/fusion_registry.gd` (融合注册系统)
