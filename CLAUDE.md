# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 1. 项目速览

**Qimela (奇美拉)** — Godot 4.5 GDScript，2D横版动作解谜。

核心机制：双锁链投射 + 怪物虚弱/融合 + 奇美拉生成。

**运行方式：** Godot 4.5 编辑器打开，主场景 `MainTest.tscn`（无构建脚本）。
```
godot --path /path/to/qimela_git
```

---

## 2. 权威真相源优先级

> **必须按此顺序查阅，不可凭记忆或代码推断。**

| 优先级 | 内容 | 权威文件 |
|--------|------|---------|
| 1 | **模块总索引** | `docs/GAME_ARCHITECTURE_MASTER.md` |
| 2 | **入口链路 + 调用链** | `docs/PROJECT_MAP.md` |
| 3 | **硬约束 + 命名规范** | `docs/CONSTRAINTS.md` |
| 4 | **实体 species_id / HP** | `docs/C_ENTITY_DIRECTORY.md` |
| 5 | **融合结果** | `docs/D_FUSION_RULES.md` |
| 6 | **物理碰撞层** | `docs/A_PHYSICS_LAYER_TABLE.md` |
| 7 | **Spine API / 动画名** | `docs/SPINE_GODOT_LATEST_INTEGRATED_STANDARD.md` |
| 8 | **Beehave 行为树 API** | `docs/BEEHAVE_REFERENCE.md` |

---

## 3. 默认最少读取白名单（≤8核心 + 2权威）

> 写代码时默认只读此清单。不在清单内的文件需要明确理由。

**核心文件（≤8个）：**
1. `docs/GAME_ARCHITECTURE_MASTER.md` — 模块总索引
2. `docs/PROJECT_MAP.md` — 入口链路与调用链
3. `docs/CONSTRAINTS.md` — 硬约束清单（本文件的补充）
4. `scene/player.gd` — 玩家总线（tick 顺序）
5. `autoload/event_bus.gd` — 全局信号接口
6. `autoload/fusion_registry.gd` — 融合规则接口
7. `docs/C_ENTITY_DIRECTORY.md` — 实体数据权威
8. `docs/D_FUSION_RULES.md` — 融合规则权威

**权威外部参考（≤2个）：**
- `docs/SPINE_GODOT_LATEST_INTEGRATED_STANDARD.md` — 涉及 Spine 动画时必读
- `docs/BEEHAVE_REFERENCE.md` — 涉及 Boss / Beehave 行为树时必读

**超出白名单时：** 先说明读取理由，再读文件。

---

## 4. GDScript 禁区速查（完整规范见 `docs/CONSTRAINTS.md`）

```gdscript
# ❌ 禁止
var x = cond ? A : B          # 无三目运算符
var n := scene.instantiate()  # 禁止 Variant 推断
collision_mask = 5             # 禁止裸数字（无注释）

# ✅ 正确
var x = A if cond else B
var n: Node = (scene as PackedScene).instantiate()
collision_mask = 4 | 64  # EnemyBody(3) + ChainInteract(7)
```

**物理层公式：第 N 层 → bitmask = `1 << (N-1)`**

---

## 5. 文件命名规范

| 类型 | 规范 | 示例 |
|------|------|------|
| `.tscn` | `PascalCase` | `MonsterWalk.tscn` |
| `.gd` | `snake_case` | `player_chain_system.gd` |
| `class_name` | `PascalCase` | `PlayerChainSystem` |

---

## 6. 关键架构速记

- **玩家 tick 顺序**（8步，不可调换）→ 见 `docs/PROJECT_MAP.md §5.1`
- **Chain 不走 ActionFSM**，是独立 overlay 系统
- **虚弱怪（hp_locked=true）** 只能被融合消灭
- **EventBus** 只用 `emit_*()` 方法，不直接 `.emit()`
- **新实体**必须先在 `docs/C_ENTITY_DIRECTORY.md` 和 `docs/D_FUSION_RULES.md` 注册

---

## 7. 文档导航索引

| 文件 | 用途 |
|------|------|
| `docs/GAME_ARCHITECTURE_MASTER.md` | **AI首选入口**，模块总表 |
| `docs/PROJECT_MAP.md` | 入口链路、节点树、调用链 |
| `docs/CONSTRAINTS.md` | 工程硬约束、命名规范、禁区 |
| `docs/A_PHYSICS_LAYER_TABLE.md` | 碰撞层详表 |
| `docs/B_GAMEPLAY_RULES.md` | 完整玩法规则 |
| `docs/C_ENTITY_DIRECTORY.md` | 实体数据权威（species_id/HP/属性） |
| `docs/D_FUSION_RULES.md` | 融合公式权威 |
| `docs/E_BEEHAVE_ENEMY_DESIGN_GUIDE.md` | Boss 行为树设计指南 |
| `docs/BEEHAVE_REFERENCE.md` | Beehave API 权威参考 |
| `docs/SPINE_GODOT_LATEST_INTEGRATED_STANDARD.md` | Spine Godot 集成规范 |
| `docs/AI_Animation_Spec_Pack_/` | 动画规范包（12份） |
| `docs/detail/*.md` | 各模块详细实现文档 |
| `CURRENT_TASK.md` | **当前任务上下文**（每次开发前填写） |
