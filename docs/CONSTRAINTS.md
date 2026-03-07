# CONSTRAINTS.md — 奇美拉（Qimela）工程硬约束与禁区

> **用途**：AI 写代码前必读的约束清单。违反任何一条均为错误输出。
> 本文件反映当前工程强制规范；如有疑问以源码注释为准。

---

## 1. 引擎与语言约束

| 约束 | 值 |
|------|-----|
| 引擎 | Godot **4.5** |
| 语言 | **GDScript**（不允许 C#、C++、外部脚本） |
| 节点版本 | Godot 4.x API（不兼容 3.x 写法） |
| 项目阶段 | 原型开发（允许测试场景，主场景 `MainTest.tscn`） |

---

## 2. GDScript 语法禁区

### 2.1 绝对禁止

```gdscript
# ❌ 三目运算符（GDScript 不支持）
var x = cond ? A : B

# ❌ Variant 类型推断 instantiate（运行时类型不安全）
var n := scene.instantiate()

# ❌ 裸碰撞层数字（无注释）
collision_mask = 5
collision_layer = 3

# ❌ 调用 Godot 3.x 已废弃 API
# 如 .connect("signal", self, "method")  →  必须用 .connect(method) 形式
```

### 2.2 必须使用的替代写法

```gdscript
# ✅ if/else 表达式代替三目
var x = A if cond else B

# ✅ 显式类型注解 instantiate
var n: Node = (scene as PackedScene).instantiate()

# ✅ 碰撞层必须附注释，使用具名 bitmask
collision_mask = 4 | 64  # EnemyBody(3) + ChainInteract(7)
# 换算公式：第 N 层 → bitmask = 1 << (N-1)

# ✅ Godot 4.x 信号连接
some_node.signal_name.connect(_on_handler)
```

---

## 3. 命名规范

| 类型 | 规范 | 示例 |
|------|------|------|
| `.tscn` 场景文件 | `PascalCase` | `MonsterWalk.tscn` |
| `.gd` 脚本文件 | `snake_case` | `player_chain_system.gd` |
| `class_name` | `PascalCase` | `class_name PlayerChainSystem` |
| 常量 | `UPPER_SNAKE_CASE` | `const MAX_HP = 10` |
| 普通变量/函数 | `snake_case` | `var is_on_floor`, `func tick(dt)` |
| 私有成员（惯例） | `_snake_case` 前缀 | `_pending_chain_fire_side` |
| Enum 枚举值 | `UPPER_SNAKE_CASE` | `enum State { IDLE, FLYING }` |

---

## 4. 物理碰撞层硬约束

**公式：第 N 层（Inspector 显示） → bitmask = `1 << (N-1)`**

| 层号 | 层名 | bitmask | 典型用途 |
|------|------|---------|---------|
| 1 | World | 1 | 静态地形 |
| 2 | PlayerBody | 2 | 玩家物理实体 |
| 3 | EnemyBody | 4 | 怪物物理实体 |
| 4 | EnemyHurtbox | 8 | 怪物受击检测 |
| 5 | ObjectSense | 16 | 雷花等感知层 |
| 6 | hazards | 32 | 危险区域 |
| 7 | ChainInteract | 64 | 锁链交互层 |

**规则：**
- 添加新碰撞实体必须查 `docs/A_PHYSICS_LAYER_TABLE.md` 确认层号
- 不允许超出已定义的 7 层（新层须先在文档注册）
- 任何 `collision_mask` / `collision_layer` 赋值必须附注释说明层名

---

## 5. 架构禁区（不可违反的设计边界）

### 5.1 链条系统（Chain）不走 ActionFSM
- 链条是独立 overlay 系统，**严禁**通过 `ActionFSM.request_*()` 触发链条发射
- 链条发射路径唯一：`_unhandled_input → _pending_chain_fire_side → ChainSystem.fire()`
- 链条动画手动触发：`PlayerAnimator.play_chain_fire(side)`，由 `_manual_chain_anim` 标志保护

### 5.2 tick 顺序不可调换
`player._physics_process()` 中 8 步顺序有严格依赖关系：
- `move_and_slide()` 必须在 `LocomotionFSM.tick()` 之前（is_on_floor 有效性依赖）
- `Animator.tick()` 必须在 `ChainSystem.tick()` 之前（链条读当帧骨骼位置）
- 不可在 `_commit_pending_chain_fire` 之前在同帧触发 fire（竞态保护）

### 5.3 EntityBase / MonsterBase 虚弱规则
- 当 `monster.hp <= monster.weak_hp` → `hp_locked = true`（进入虚弱态）
- 虚弱态不可被普通攻击击杀，只有融合才能消灭
- `MonsterHostile`（融合失败产物）**无**虚弱态

### 5.4 奇美拉互动优先于链条发射
```
鼠标左键 → 检查 active_slot LINKED && is_chimera
    是 → chimera.on_player_interact(self)  ← 优先
    否 → 正常发射链条
```

### 5.5 ChimeraStoneSnake 不可被链条链接
- 此奇美拉为攻击型，设计上 `ChainInteract` 层设置为不可链接
- 不允许代码绕过此限制

---

## 6. 实体数据权威源

| 数据 | 权威文件 | 禁止做法 |
|------|---------|---------|
| `species_id` | `docs/C_ENTITY_DIRECTORY.md` | 不可从代码猜测/推断 species_id |
| 融合结果 | `docs/D_FUSION_RULES.md` | 不可从代码猜测融合结果 |
| 物理层号 | `docs/A_PHYSICS_LAYER_TABLE.md` | 不可从代码猜测层号 |
| 动画名称 | `docs/detail/ANIMATION_SYSTEM.md` + `docs/AI_Animation_Spec_Pack_/` | 不可随意命名动画 |

---

## 7. 动画系统约束

### 7.1 双轨道架构
- **Track 0（移动轨）**：始终由 `LocomotionFSM` 驱动，反映移动状态
- **Track 1（动作轨）**：由 `ActionFSM` 或手动触发覆盖，无动作时透明
- 不允许直接操作 `AnimationPlayer`，必须通过 `PlayerAnimator` API

### 7.2 Spine 动画规范
- 所有 Spine 动画名称必须查 `docs/AI_Animation_Spec_Pack_/` 目录确认
- 权威参考：`docs/SPINE_GODOT_LATEST_INTEGRATED_STANDARD.md`
- Spine API 调用方式以 `docs/SPINE_GODOT_LATEST_INTEGRATED_STANDARD.md` 为准（不可凭记忆）

---

## 8. Beehave 行为树约束

- Boss 类敌人（`stone_mask_bird/`, `stone_eyebug/`）使用 **Beehave** 插件行为树
- 权威参考：`docs/BEEHAVE_REFERENCE.md`
- 行为树节点分两类：
  - `conditions/*.gd`：返回 `SUCCESS`/`FAILURE` 的无副作用条件检查
  - `actions/*.gd`：有副作用的动作节点
- 不允许在条件节点中执行副作用操作

---

## 9. EventBus 使用约束

- **只能**通过 `EventBus.emit_*()` 方法发送事件，禁止直接 `.emit()`
- 信号接收用 `.connect()`，不允许 `await` 全局信号（会阻塞主线程）
- 添加新信号必须同时添加对应的 `emit_*()` 封装方法

---

## 10. 输出规范（生成新实体时的检查清单）

新增怪物/奇美拉时必须：
1. 在 `docs/C_ENTITY_DIRECTORY.md` 注册 `species_id`、属性、HP 数值
2. 在 `docs/D_FUSION_RULES.md` 补充融合规则
3. 场景文件用 `PascalCase`，脚本用 `snake_case`
4. 设置正确的 `collision_layer`/`collision_mask`，加注释
5. 继承正确的基类（`MonsterBase` 或 `ChimeraBase`）
6. 如使用 Beehave，参照 `docs/BEEHAVE_REFERENCE.md` 和 `docs/E_BEEHAVE_ENEMY_DESIGN_GUIDE.md`

---

## 11. 文件读取最少原则

> AI 写代码前应优先查阅此约束文档，减少冗余文件读取。

**最小读取白名单**（见 `CLAUDE.md` 第4节）：写代码前不应超出白名单范围，除非任务明确需要。
