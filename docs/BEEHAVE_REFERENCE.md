# Beehave 2.9.x 完整参考文档（基于官方源码 + 实战校对）

> 适用版本：Beehave 2.9.2 / Godot 4.5.x
> 本文档直接从官方源码提取，并结合动态优先级 Boss AI 实战项目校对。
> 本次修订已额外完成两项整理：**补全开头总表遗漏节点**、**把源码事实与项目实践显式拆开标注**。

---

## 阅读标记：源码事实 vs 项目实践

为避免 AI 把“源码真实行为”和“当前项目里验证有效的推荐写法”混成一锅粥，本文统一使用以下标记：

- **【源码事实】**：可直接视为 Beehave 2.9.2 源码行为、API、属性或通用机制说明
- **【项目实践】**：已经在动态优先级 Boss AI 中验证有效，但**不是**插件唯一正确写法
- **【适用范围】**：当某条建议只适用于 `SelectorReactiveComposite` / `SequenceReactiveComposite` 这类结构，或只适用于 2D 横向动作项目，会明确写出范围

阅读时请优先区分这三类信息。这样 AI 读文档后，不会把“项目经验”误认成“插件公理”。

---

## 在 .tscn 场景文件中使用 Beehave 节点的正确方式

这是最容易踩的工程坑，**必须先读**。

Beehave 的所有节点（`BeehaveTree`、`SelectorComposite`、`CooldownDecorator` 等）都是 GDScript 的 `class_name`，**不是 Godot 原生 C++ 类**。在 `.tscn` 文件里，`type=` 字段只接受原生类，因此：

```
# 错误写法——Godot 无法识别，加载时报 "Cannot get class 'BeehaveTree'"
[node name="BeehaveTree" type="BeehaveTree" parent="."]

# 正确写法——用 Node 作为基础类型，再用 script= 挂载 Beehave 的 .gd 文件
[node name="BeehaveTree" type="Node" parent="."]
script = ExtResource("bt_tree")

# 对应的 ext_resource 声明：
[ext_resource type="Script" path="res://addons/beehave/nodes/beehave_tree.gd" id="bt_tree"]
```

**所有 Beehave 内置节点对应的脚本路径（已补全，不再漏掉 Blackboard 内置叶节点）：**

| 节点 | 脚本路径（`res://addons/beehave/...`） |
|---|---|
| BeehaveTree | `nodes/beehave_tree.gd` |
| SelectorComposite | `nodes/composites/selector.gd` |
| SelectorReactiveComposite | `nodes/composites/selector_reactive.gd` |
| SequenceComposite | `nodes/composites/sequence.gd` |
| SequenceReactiveComposite | `nodes/composites/sequence_reactive.gd` |
| SequenceStarComposite | `nodes/composites/sequence_star.gd` |
| SequenceRandomComposite | `nodes/composites/sequence_random.gd` |
| SelectorRandomComposite | `nodes/composites/selector_random.gd` |
| SimpleParallelComposite | `nodes/composites/simple_parallel.gd` |
| InverterDecorator | `nodes/decorators/inverter.gd` |
| AlwaysFailDecorator | `nodes/decorators/failer.gd` |
| AlwaysSucceedDecorator | `nodes/decorators/succeeder.gd` |
| LimiterDecorator | `nodes/decorators/limiter.gd` |
| CooldownDecorator | `nodes/decorators/cooldown.gd` |
| DelayDecorator | `nodes/decorators/delayer.gd` |
| TimeLimiterDecorator | `nodes/decorators/time_limiter.gd` |
| RepeaterDecorator | `nodes/decorators/repeater.gd` |
| UntilFailDecorator | `nodes/decorators/until_fail.gd` |
| BlackboardSetAction | `nodes/leaves/blackboard_set.gd` |
| BlackboardEraseAction | `nodes/leaves/blackboard_erase.gd` |
| BlackboardHasCondition | `nodes/leaves/blackboard_has.gd` |
| BlackboardCompareCondition | `nodes/leaves/blackboard_compare.gd` |
| Blackboard | `blackboard.gd` |

自定义叶节点（你自己写的 `extends ActionLeaf` / `extends ConditionLeaf`）同样用 `type="Node"` + `script=` 挂载。

---

## 一、返回状态常量

`BeehaveNode` 和 `BeehaveTree` 都定义了 `enum { SUCCESS, FAILURE, RUNNING }`。

```gdscript
return SUCCESS    # 推荐写法，简洁
return FAILURE
return RUNNING

return BeehaveNode.SUCCESS   # 也合法，只是啰嗦，不是错误
```

> **注意**：两种写法都能用。`BeehaveNode.SUCCESS` 不是"错误"，只是没必要加前缀。

---

## 二、BeehaveTree（根节点）

**脚本路径：** `addons/beehave/nodes/beehave_tree.gd`
**继承：** `Node`

### Inspector 属性

| 属性名 | 类型 | 默认值 | 说明 |
|---|---|---|---|
| `enabled` | bool | true | 是否启用自动 tick |
| `tick_rate` | int | 1 | 每 N 帧执行一次（1 = 每帧）。使用 tick_rate > 1 时，Condition 变化响应最多延迟 tick_rate-1 帧（T-19）。安全敏感状态切换（被攻击、死亡）不应使用 tick_rate > 1。 |
| `actor_node_path` | NodePath | （空） | 指定 actor 节点路径 |
| `process_thread` | ProcessThread | PHYSICS | 执行线程模式，见下方重要说明 |
| `blackboard` | Blackboard | null | 外部 Blackboard；不指定则自动创建内部 Blackboard |
| `actor` | Node | （父节点） | actor 引用，也可代码直接赋值 |
| `custom_monitor` | bool | false | 在性能监视器中单独显示耗时 |

### actor 的指定方式（源码确认）

BeehaveTree **不强制**必须是角色的直接子节点。actor 的确定优先级为：

1. 代码直接赋值：`tree.actor = my_node`
2. Inspector 设置 `actor_node_path`
3. 以上都没有时：**自动取父节点**（`get_parent()`）

```
# 推荐结构（最省事，利用自动取父节点）
CharacterBody2D
└── BeehaveTree   <- actor 自动为 CharacterBody2D

# 也合法（Tree 放别处，手动指定 actor）
World
├── MyActor (CharacterBody2D)
└── AIManager
    └── BeehaveTree   <- 需要设置 actor_node_path 或代码赋值 actor
```

### ProcessThread 枚举（MANUAL 有重要副作用）

```gdscript
enum ProcessThread { IDLE, PHYSICS, MANUAL }
```

| 值 | 说明 |
|---|---|
| `PHYSICS`（默认） | 每物理帧自动执行 |
| `IDLE` | 每渲染帧自动执行 |
| `MANUAL` | **不自动执行** |

> MANUAL 的源码行为（第47行）：
> ```gdscript
> self.enabled = self.enabled and process_thread != ProcessThread.MANUAL
> ```
> 切换到 MANUAL 时会**强制将 `enabled` 置为 false**。这意味着：
> - 切到 MANUAL 后，再在 Inspector 勾选 `enabled` 也不会自动 tick
> - MANUAL 模式下只能通过代码手动调用 `tree.tick()`
> - 如果你把 `process_thread` 切回 PHYSICS/IDLE，需要再手动 `tree.enable()`

### BeehaveTree 与 _physics_process 的执行顺序

BeehaveTree 使用 `_physics_process` 触发 tick（PHYSICS 模式下）。如果 actor 自身也有 `_physics_process`，**actor 的 `_physics_process` 先执行，BeehaveTree 的 tick 后执行**（场景树顺序决定）。

实际顺序：`actor._physics_process()` -> `move_and_slide()` -> `BT.tick()` -> 叶节点设置 `velocity`

这意味着叶节点设置的 `velocity` 在**下一帧**的 `move_and_slide` 才会生效，不是当帧。

### 信号

```gdscript
signal tree_enabled
signal tree_disabled
```

### 方法

```gdscript
func tick() -> int                          # 手动触发一次 tick
func get_running_action() -> ActionLeaf     # 获取当前 RUNNING 的 ActionLeaf
func get_last_condition() -> ConditionLeaf  # 获取上次执行的 ConditionLeaf
func get_last_condition_status() -> String  # 返回 "SUCCESS"/"FAILURE"/"RUNNING"
func interrupt() -> void                    # 中断当前运行节点
func enable() -> void                       # 等同于 self.enabled = true
func disable() -> void                      # 等同于 self.enabled = false
```

> **【T-18 实测 Bug】`enabled=false` + `enabled=true` 不重置树状态：**
> `enabled=false`（或 `disable()`）会同帧正确触发 `interrupt()`，但**不会重置 `BeehaveTree.status`**。
> re-enable 后 status 仍为 RUNNING，`BeehaveTree.tick()` 跳过 `before_run`，节点直接进入 `tick`。
> 任何依赖 `before_run` 做初始化的节点都会永久跳过初始化。
>
> **正确做法：** re-enable 前确保子节点已自然返回非 RUNNING，或在 re-enable 后手动调用 `tree.interrupt()`，或重建整棵树。

---

## 三、Blackboard

**脚本路径：** `addons/beehave/blackboard.gd`
**继承：** `Node`（不是 Resource！）

### 完整 API（源码确认）

```gdscript
func set_value(key: Variant, value: Variant, blackboard_name: String = "default") -> void
func get_value(key: Variant, default_value: Variant = null, blackboard_name: String = "default") -> Variant
func has_value(key: Variant, blackboard_name: String = "default") -> bool
func erase_value(key: Variant, blackboard_name: String = "default") -> void
func keys() -> Array[String]
```

> `erase_value` 的实现是把值设为 `null`，不是真正从字典删除。`has_value` 判断"存在且不为 null"，效果等同于删除。

### 多 Actor 共享 Blackboard 的命名空间规则（T-20 实测）

多个 NPC 共享同一个 Blackboard 节点时，**命名空间决定数据是否互相污染**：

| 命名空间写法 | 可见范围 | 适用场景 |
|---|---|---|
| 默认不传（`"default"`） | **所有 Actor 共享** | 真正全局的状态（游戏阶段、全局警报）；**禁止**用于 NPC 自身状态 |
| `str(actor.get_instance_id())` | 当前 Actor 独占 | NPC 自身的所有状态（血量、目标、冷却等） |
| 自定义字符串 | 显式共享 | 多 NPC 协作的共享信号 |

```gdscript
# 错误：default 命名空间，所有 NPC 互相覆盖
blackboard.set_value("hp", 100)
var hp = blackboard.get_value("hp")   # 读到的可能是别的 NPC 写的值

# 正确：用 actor 实例 ID 作为命名空间
var actor_id := str(actor.get_instance_id())
blackboard.set_value("hp", 100, actor_id)
var hp = blackboard.get_value("hp", 0, actor_id)
```

> Beehave 内部状态（`running_child` 等）也使用 `str(actor.get_instance_id())` 命名空间，不会与用户数据冲突。

### Blackboard 数据的生命周期陷阱（实战发现）

Blackboard 的数据**跨帧持久存在**，不会自动清除。这在 SelectorReactive 里容易造成"脏数据"问题：

```
SelectorReactiveComposite
├── SequenceA
│   ├── ConditionA  <- 写入 blackboard["player"]
│   └── ActionA     <- 读取 blackboard["player"]
├── SequenceB
│   └── ActionB     <- 也读取 blackboard["player"]  <- 危险！
```

每帧 SelectorReactive 从头开始，ConditionA 先执行。如果 ConditionA 失败并 `erase_value("player")`，ActionB 这帧不会被 tick（SequenceA FAILURE 后 Selector 继续往下），但**上一帧**ConditionA 还在 SUCCESS 时写入的 player 已经在 blackboard 里了。

更危险的情况：SequenceB 排在 SequenceA **之后**，当 ConditionA 失败时，SequenceA FAILURE，Selector 继续 tick SequenceB，此时 ConditionA 刚刚 `erase_value("player")`，ActionB 读到 null，正确。

但如果 SequenceB 里有 ConditionB 检查近战范围，而近战 ConditionB 依赖的是 blackboard["player"]（上帧由 ConditionA 写入的旧值）——ConditionA 已失败清除了 player，ConditionB 读不到 player，也 FAILURE。这看起来正确，但如果 ConditionB **不依赖 blackboard 而是自己感知**，就能正确工作。

**原则：每个 ConditionLeaf 应该自给自足地感知，不依赖其他分支写入的 blackboard 值。**

---

## 四、BeehaveNode（所有节点基类）

```gdscript
# 必须重写
func tick(actor: Node, blackboard: Blackboard) -> int:
    return SUCCESS

# 可选重写
func before_run(actor: Node, blackboard: Blackboard) -> void: pass
func after_run(actor: Node, blackboard: Blackboard) -> void: pass

# 重写时必须调用 super()！
func interrupt(actor: Node, blackboard: Blackboard) -> void:
    super(actor, blackboard)
```

### before_run 的调用时机（源码确认，重要）

`before_run` **不是每帧都调用**，只在节点从"未运行"状态首次进入时调用一次。

- `SelectorReactiveComposite` 里：每帧对**非 running_child** 的子节点调用 `before_run`，然后立即 tick
- `SequenceReactiveComposite` 里：每帧从 i=0 重新开始，对非 running_child 的节点调用 `before_run`

这意味着在 SelectorReactive 里，如果你的子节点不是 running_child，**每帧都会调用它的 before_run**。如果 before_run 里有重置逻辑（如 `_is_waiting = false`），会被每帧重置。

---

## 五、叶节点

### ActionLeaf
可跨帧运行，可返回 SUCCESS / FAILURE / RUNNING。

### ConditionLeaf
只检查单一条件，**只返回 SUCCESS 或 FAILURE，绝不返回 RUNNING**。

---

## 六、内置叶节点

### BlackboardSetAction / BlackboardEraseAction / BlackboardHasCondition / BlackboardCompareCondition

这四个节点在 Inspector 中填写 GDScript **表达式字符串**。

> 表达式的执行上下文（源码确认）：
> 调用方式是 `expression.execute([], blackboard)`，第二个参数是 `base_instance`，即 Blackboard 对象本身作为 `self`。
> 因此表达式里的方法调用实际上是**直接调用 Blackboard 的方法**：
>
> ```
> # 正确——直接写方法名，Blackboard 是隐式的 self
> get_value("distance")
> get_value("health") < 30
>
> # 错误——不存在名为 blackboard 的变量
> blackboard.get_value("distance")
>
> # 错误——actor 不在表达式上下文中
> actor.global_position
> ```

---

## 七、组合节点（Composite Nodes）

### 7.1 SequenceComposite

依次执行所有子节点，全部 SUCCESS 才返回 SUCCESS。

**【源码事实】跨帧行为：**
- 内部用 `successful_index` 跟踪进度，跳过已成功的节点
- 遇到 RUNNING：记录位置，下帧从此处继续
- 遇到 FAILURE：**`successful_index` 重置为 0**，下帧从头开始
- 全部 SUCCESS 后：`successful_index` 重置为 0，返回 SUCCESS

**【项目实践】在动态优先级 AI 里的建议：**
- 当本节点被放在 `SelectorReactiveComposite` 之下，且子节点里既有条件又有动作时，`successful_index` 的推进可能让前面的条件在后续帧被跳过
- 因此，**“条件 + 技能 Action” 这一类需要每帧重检条件的序列**，更推荐用 `SequenceReactiveComposite`
- 这是一条**项目推荐写法**，不是插件层面的绝对禁令；静态多步骤任务仍然非常适合 `SequenceComposite`


### 7.2 SequenceStarComposite

与 SequenceComposite 有本质差异，不是"基本相同"：

| 情况 | SequenceComposite | SequenceStarComposite |
|---|---|---|
| 遇到 FAILURE | **重置** `successful_index = 0`，下次从头 | **不重置** `successful_index`，保留进度 |
| 遇到 RUNNING | 记录位置，下帧继续 | 同左 |
| interrupt() | 重置 | 重置 |

```
# SequenceComposite 的使用场景：
# 条件+行为的序列，失败后需要重新检查前置条件
SequenceComposite
├── CanSeePlayerCondition   <- 失败时下次会重新检查这里
└── ChaseAction

# SequenceStarComposite 的使用场景：
# 多步骤任务，某步失败后下次跳过已完成的步骤继续推进
SequenceStarComposite
├── OpenDoorAction          <- 成功后不再重复
├── EnterRoomAction         <- 成功后不再重复
└── FindTargetAction        <- 失败时下次直接从这里继续，不会重开门
```

### 7.3 SelectorComposite

依次尝试子节点，遇到第一个 SUCCESS/RUNNING 返回，全部 FAILURE 才返回 FAILURE。

- 内部有 `last_execution_index`，记录上次停下的位置
- 遇到 RUNNING 时停在该分支，下帧**从 last_execution_index 继续**（不从头）
- `interrupt()` 时重置 `last_execution_index`

### 7.4 SequenceReactiveComposite

**每帧从第一个子节点（i=0）重新开始**，遇到 RUNNING 时：
1. 调用 `_reset()`（清除 `previous_failure_index`）
2. 记录 `running_child`
3. 返回 RUNNING

下帧再次从 i=0 开始，对所有节点重新 tick（non-running_child 会先调 before_run）。

```gdscript
# sequence_reactive.gd 核心逻辑（简化）
for i in range(children.size()):
    var c = children[i]
    if c != running_child:
        c.before_run(actor, blackboard)   # <- 每帧对非running_child调用before_run！
    var response = c._safe_tick(...)
    match response:
        FAILURE: return FAILURE
        RUNNING: running_child = c; return RUNNING  # 后面的节点本帧不被tick
# 全部SUCCESS
return SUCCESS
```

```
# 正确用途：前置位置只放 ConditionLeaf，末尾才放 ActionLeaf
SequenceReactiveComposite
├── CanSeePlayerCondition   <- 每帧重新检查，失效则中断下面的 Action
└── ChaseAction             <- 唯一的 RUNNING Action，稳定运行
```

**【D-16 危险陷阱】【源码事实 / T-29 实测】SequenceReactive 非末尾位置禁止放可返回 RUNNING 的 ActionLeaf：**

```
# 错误写法！ActionA 完成后会导致 ActionB 永远被中断
SequenceReactiveComposite
├── ActionA(N帧→SUCCESS)   <- 致命陷阱
└── ActionB(永远RUNNING)   <- 每 N+1 帧就被 interrupt 一次，永远无法稳定运行
```

陷阱根因：ActionA 完成后，ActionB 成为 `running_child`。下帧 ActionA ≠ `running_child` → `ActionA.before_run()` 被调用 → `_run_count` 重置 → `ActionA.tick()` 返回 RUNNING → `ActionB.interrupt()` 被调用，ActionB 被中断。如此无限循环，ActionB 每次只能运行 1 帧。

**注意：用 `AlwaysSucceedDecorator` 包裹 ActionA 也无法解决此问题。** AlwaysSucceed 返回 SUCCESS 后，其 `running_child` 被清空，下帧 ActionA 仍然被重置（T-29 场景 C 实测确认）。

**【项目实践】与 `SequenceComposite` / `SequenceStarComposite` 的选择：**
- 技能序列（条件 + 冷却 + Action） -> 更推荐 **`SequenceReactiveComposite`**，保证每帧重新检查条件
- 静态多步骤任务（不需要每帧重检条件） -> 可用 `SequenceComposite` 或 `SequenceStarComposite`
- 这部分属于**推荐搭配**，不是源码硬性规则

### 7.5 SelectorReactiveComposite

**源码关键行为（实战验证）：**

```gdscript
# selector_reactive.gd 核心逻辑（简化）
for i in range(children.size()):
    var c = children[i]
    if c != running_child:
        c.before_run(actor, blackboard)   # <- 每帧对非running_child调用before_run！
    var response = c._safe_tick(actor, blackboard)
    match response:
        SUCCESS: return SUCCESS           # 立即返回，不继续tick后面的节点
        FAILURE: c.after_run(...)         # 继续循环
        RUNNING: return RUNNING           # 立即返回，不继续tick后面的节点
# 全部FAILURE
return FAILURE
```

**关键特性：**
1. 每帧**从第一个子节点重新开始**（不记忆上次位置）
2. 遇到 RUNNING 立即 `return RUNNING`，**后面的子节点本帧不会被 tick**
3. 非 `running_child` 的节点**每帧都会被调用 `before_run`**
4. 遇到 RUNNING 时中断旧的 `running_child`（如果不同的话）

**【项目实践】在动态优先级 AI 里，它通常会作为顶层主力 Selector，配合 `SequenceReactiveComposite` 使用。**

### 7.6 SequenceRandomComposite

子节点**每帧重新随机排序**后执行（类似 SequenceComposite 语义，但顺序随机）。

**Inspector 属性：**
- `random_seed`：随机种子（0 = 每帧使用随机种子）
- `use_weights`：是否按权重加权洗牌
- `resume_on_failure`：子节点 FAILURE 后，下次 tick 是否跳过已完成的节点（**不是重试**，是跳过 bag 中已消耗的节点，bag 耗尽返回 FAILURE）
- `resume_on_interrupt`：被外部 interrupt 后，下次 tick 是否保留 bag 状态继续未完成节点

**信号：** `reset(new_order: Array)`

**T-26 实测关键结论（源码确认）：**
- 每帧洗牌是真随机，**同一 `random_seed` 在不同帧可产生不同顺序**（因内部 RNG 状态推进）
- `resume_on_failure=true`：第一个节点 SUCCESS、第二个 FAILURE 时 → 该轮 bag 耗尽返回 FAILURE，**不会跳回去重试**
- `resume_on_interrupt=true`：外部 interrupt 后，bag 状态保留，下次 tick 从剩余未执行节点继续

### 7.7 SelectorRandomComposite

子节点**每帧重新随机排序**后尝试，遇第一个 SUCCESS 立即返回（类似 SelectorComposite 语义）。

**Inspector 属性：** `random_seed`、`use_weights`（无 `resume` 选项）

**T-26 实测关键结论：**
- 每帧重新洗牌，顺序完全随机
- 遇到第一个 SUCCESS 立即返回，后续节点本帧不被 tick

### 7.8 SimpleParallelComposite

**必须恰好 2 个子节点**。主任务（index 0）决定整体结果，后台任务（index 1）持续执行且结果被忽略。

Inspector 属性：
- `secondary_node_repeat_count`：后台任务重复次数（0 = 无限循环）
- `delay_mode`：主任务结束后的行为

**`delay_mode` 精确语义（T-27 实测确认）：**

| delay_mode | 主任务 FAILURE/SUCCESS 后行为 |
|---|---|
| `false`（默认）| 主任务结束的**同帧**立即 interrupt secondary，同帧返回结果 |
| `true` | 主任务结束后，等 secondary **完成当前整轮**（tick→非RUNNING）再返回结果 |

注意：`delay_mode=true` 是等 secondary 完成**当前完整的一次 tick 循环**，不是"等当帧 tick 结束"。如果 secondary 本帧 RUNNING，则主任务会在下帧或更多帧后才返回。

**`secondary_repeat_count` 语义（T-07/T-27 实测确认）：**
- 该计数在**每次 `before_run` 时重置**，是每轮的局部上限，不是全局总次数（D-06）
- `repeat_count=1`：secondary 运行一次 SUCCESS 后停止，之后每帧只有 primary 独自 tick（T-27 场景 D 确认）

---

## 八、装饰节点（Decorator Nodes）

装饰节点**必须有且只有一个子节点**。

### 8.1 InverterDecorator
SUCCESS <-> FAILURE，RUNNING 不变。

### 8.2 AlwaysFailDecorator
SUCCESS/FAILURE -> FAILURE，**RUNNING -> RUNNING**（不是 FAILURE）。

### 8.3 AlwaysSucceedDecorator
SUCCESS/FAILURE -> SUCCESS，**RUNNING -> RUNNING**（不是 SUCCESS）。

> **常见误用**：用 `AlwaysSucceedDecorator` 包裹一个永远返回 RUNNING 的 Action（如巡逻），期望让 Selector 认为此分支"成功"并停下来。但子节点 RUNNING 时它也返回 RUNNING，Selector 会停在此分支持续执行——这其实是你想要的效果，**直接不用包装**，Selector 遇到 RUNNING 分支就会停在那里。

### 8.4 LimiterDecorator

【**实测纠正，T-16**】**官方文档描述"限制执行次数"是错误的。** 实际语义是：**限制子节点连续处于 RUNNING 状态的帧数上限**。

- 子节点每次处于 RUNNING 时 `current_count++`
- `current_count >= max_count` 时触发 `interrupt()` 并返回 FAILURE
- **子节点一旦返回非 RUNNING（SUCCESS 或 FAILURE），`_reset_counter()` 立即清零计数**
- `interrupt()` 也会清零计数

**实用矩阵（T-16 实测）：**

| 子节点行为 | LimiterDecorator 效果 |
|---|---|
| 立即 SUCCESS / FAILURE | `max_count` 完全无效，子节点无限执行 |
| RUNNING N 帧后 SUCCESS | `max_count` 无效（SUCCESS 时 reset） |
| 永远 RUNNING | ✅ 有效：累积 `max_count` 帧后 interrupt |

> **`max_count` 默认值为 0（源码第11行）**：`current_count < max_count` 的判断在 max_count=0 时第一次 tick 就直接进入 FAILURE 分支。**使用时必须手动设置 max_count >= 1**，否则等同于"禁用"该节点（立即失败）。

Inspector 属性：
- `max_count`：子节点连续处于 RUNNING 的最大帧数（**必须 >= 1，默认 0 = 立即失败**）

计数存储在 Blackboard 中（带 actor 命名空间）。

### 8.5 CooldownDecorator

子节点执行完（非 RUNNING）后，在 `wait_time` 秒内直接返回 FAILURE。

**【源码事实】**
- `wait_time`：冷却时间（float，秒）
- 用 `Time.get_ticks_msec()` 计算（2.9.0 修复了此前用物理帧计算的 Bug）
- **`interrupt()` 时冷却时间重置为 0**

**【项目实践】【适用范围：`SelectorReactiveComposite` + `SequenceReactiveComposite` 动态优先级结构】**

在动态优先级 AI 中，这个节点**很容易因为分支切换而失效**。原因不是它“设计错误”，而是源码里 `interrupt()` 的确会清空冷却，而 `SelectorReactiveComposite` 又会频繁打断旧分支。

**实际发生的情况：**
1. 远程攻击技能执行完，`CooldownDecorator` 开始 3 秒冷却
2. 下一帧近战技能触发，`SelectorReactive` 切换 running_child
3. `_interrupt_children()` 被调用 -> `CooldownDecorator.interrupt()` -> **冷却归零**
4. 下一帧远程序列重新执行，冷却已清除，又立刻开火
5. 这反过来又触发切换 -> 冷却再次归零 -> 无限循环

**调试方法：**
如果 Boss 的某个技能序列被异常频繁触发，且其他行为（追击 / 巡逻）消失，很可能就是 `CooldownDecorator` 被反复 `interrupt()` 重置导致的。通过在 `ConditionLeaf` 加 `print` 输出观察哪些节点在执行，可快速定位。

**项目内替代方案：在 `ActionLeaf` 内自管理冷却。**

```gdscript
# 在 ActionLeaf 里自己管理冷却，存在 blackboard，interrupt 不会影响它
const COOLDOWN_KEY = "cooldown_my_skill"

func tick(actor: Node, blackboard: Blackboard) -> int:
    var actor_id := str(actor.get_instance_id())
    var end_time: float = blackboard.get_value(COOLDOWN_KEY, 0.0, actor_id)
    if Time.get_ticks_msec() < end_time:
        return FAILURE   # 冷却中，让 Sequence 失败，Selector 往下走

    # ... 执行技能逻辑 ...

    # 技能完成后才设置冷却（不在 before_run 或 interrupt 里清除）
    blackboard.set_value(COOLDOWN_KEY, Time.get_ticks_msec() + cooldown * 1000, actor_id)
    return SUCCESS

func interrupt(actor: Node, blackboard: Blackboard) -> void:
    # 不清除 COOLDOWN_KEY，让冷却自然等待
    super(actor, blackboard)
```

**【项目实践结论】**
- 静态 AI（没有 `SelectorReactiveComposite` 动态切分支）或不会被 `interrupt()` 打断的固定序列：`CooldownDecorator` 可以正常使用
- 动态优先级 Boss AI：更推荐把冷却写进 `ActionLeaf`


### 8.6 DelayDecorator

**执行前**等待 `wait_time` 秒，等待期间返回 RUNNING，之后才执行子节点。

- `interrupt()` 时计时重置
- 用 `get_physics_process_delta_time()` 累积

### 8.7 TimeLimiterDecorator

给子节点设定**最大运行时间**，超时后中断并返回 FAILURE。

- `wait_time`：超时时长（秒）
- `before_run()` 时重置计时器为 0.0
- `interrupt()` 时也重置计时器（调用 super 前先清零）

计时使用 delta 逐帧累加，存入 Blackboard（key = `"time_limiter_<instance_id>"`）。

**【D-15 危险陷阱】【源码事实 / T-24 实测】禁止在 `SelectorReactive` 路径下依赖 `TimeLimiterDecorator` 超时：**

`interrupt()` 会清零计时器。在 `SelectorReactive` 路径下，每当高优先级分支切换回来时，`interrupt()` 被调用，计时器归零。TimeLimiter 永远无法累积到 `wait_time`，超时逻辑永远不触发。原理与 D-01（CooldownDecorator）完全相同。

### 8.8 RepeaterDecorator

重复执行子节点 `repetitions` 次（默认 1）。子节点每次 SUCCESS 计一次，FAILURE 立即返回 FAILURE，RUNNING 等待不计数。

> 属性名是 `repetitions`，不是 `repeat_count` 或 `max_count`。

### 8.9 UntilFailDecorator

| 子节点状态 | 该节点返回 |
|---|---|
| SUCCESS | RUNNING（继续循环） |
| RUNNING | RUNNING |
| FAILURE | **SUCCESS**（结束） |

---

## 九、脚本模板

**文件路径：** `script_templates/BeehaveNode/default.gd`

> 仅 GitHub 源码仓库版本包含此目录。通过 Godot 资产库下载的版本可能不包含 `script_templates/`。如需使用，可手动在项目根目录创建：

```gdscript
# 手动创建路径：res://script_templates/BeehaveNode/default.gd
# meta-name: Default
# meta-default: true
extends _BASE_

func tick(actor: Node, blackboard: Blackboard) -> int:
    return SUCCESS
```

---

## 十、极易出错汇总

本节每条都显式标记为 **【源码事实】** 或 **【项目实践】**，避免把项目经验误看成插件公理。

### 错误 1【源码事实】：.tscn 场景文件中不能用 class_name 作为 type

```
# 错误 报错：Cannot get class 'BeehaveTree'
[node name="BeehaveTree" type="BeehaveTree" parent="."]

# 正确
[node name="BeehaveTree" type="Node" parent="."]
script = ExtResource("bt_tree")
```

所有 Beehave 内置节点和自定义叶节点都适用此规则。详见文档开头的路径对照表。

### 错误 2【源码事实】：Blackboard 方法名

```gdscript
# 错误
blackboard.get("key")
blackboard.set("key", value)

# 正确
blackboard.get_value("key")
blackboard.set_value("key", value)
blackboard.has_value("key")
blackboard.erase_value("key")
```

### 错误 3【源码事实】：内置 Blackboard 节点的表达式中不能用 blackboard 变量名

```gdscript
# 表达式里 Blackboard 是隐式 self，直接调方法即可：
# 正确
get_value("health")
get_value("dist") < 100

# 错误（不存在 blackboard 这个变量名）
blackboard.get_value("health")

# 错误（actor 不在表达式上下文中）
actor.global_position
```

### 错误 4【源码事实】：SequenceComposite 和 SequenceStarComposite 的根本差异

```
SequenceComposite：FAILURE 后 successful_index 重置为 0，下次从头开始
SequenceStarComposite：FAILURE 后 successful_index 保留，下次跳过已成功的节点

# 用条件+行为组合时用 SequenceComposite 或 SequenceReactiveComposite
# 用多步骤任务且不想重做已完成步骤时用 SequenceStarComposite
```

### 错误 5【源码事实 + T-16 实测纠正】：LimiterDecorator 不是"次数限制器"

```gdscript
# 【T-16 实测】LimiterDecorator 限制的是子节点连续 RUNNING 的帧数，不是执行次数
# 子节点立即 SUCCESS / FAILURE -> _reset_counter() 清零 -> max_count 完全无效

# 错误用法：试图限制 SummonAction 执行次数（SummonAction 立即返回 SUCCESS）
LimiterDecorator (max_count=3)
└── SummonAction   # 每次 SUCCESS 都清零，无限执行

# 正确用法（唯一有效场景）：限制子节点持续 RUNNING 的时长（帧数）
LimiterDecorator (max_count=60)   # 最多持续 60 帧（约1秒）
└── ChaseAction   # 永远返回 RUNNING 的动作

# 若要限制执行次数，应在 ActionLeaf 内自管理计数，存入 Blackboard
```

> max_count 默认 0 = 立即失败，使用时必须设置 max_count >= 1。

### 错误 6【源码事实】：AlwaysSucceedDecorator 和 AlwaysFailDecorator 不覆盖 RUNNING

```gdscript
# 子节点 RUNNING 时，两者都直接返回 RUNNING
# 不能用来"把 RUNNING 变成 SUCCESS/FAILURE"

# 想让 Selector 停在某个 RUNNING 分支？
# -> 不需要任何装饰器，Selector 遇到 RUNNING 本身就会停留
```

### 错误 7【源码事实】：三个时间装饰节点区别

| 节点 | 时机 | 等待期返回 | 触发结果 |
|---|---|---|---|
| `DelayDecorator` | **执行前**等待 N 秒 | RUNNING | 等完才执行子节点 |
| `CooldownDecorator` | **执行后**冷却 N 秒 | — | 冷却中直接 FAILURE |
| `TimeLimiterDecorator` | **执行中**限制总时长 | — | 超时中断返回 FAILURE |

### 错误 8【源码事实】：MANUAL 模式会强制将 enabled 置为 false

```gdscript
# 源码（beehave_tree.gd:47）：
self.enabled = self.enabled and process_thread != ProcessThread.MANUAL

# 切到 MANUAL 后：
# - enabled 被强制设为 false
# - 在 Inspector 重新勾选 enabled 也不会自动 tick
# - 只能用代码：tree.tick()
# - 若要恢复自动，需先改回 process_thread = PHYSICS/IDLE，再 tree.enable()
```

### 错误 9【源码事实】：SimpleParallelComposite 必须恰好 2 个子节点

不是"至少 2 个"，多或少都有警告。

### 错误 10【源码事实】：重写 interrupt() 必须调 super()

```gdscript
func interrupt(actor: Node, blackboard: Blackboard) -> void:
    my_cleanup()
    super(actor, blackboard)   # 必须！否则调试器消息丢失
```

### 错误 11【源码事实】：BeehaveTree 只能有一个直接子节点

```
# 错误 两个直接子节点会产生配置警告
BeehaveTree
├── SequenceComposite
└── SelectorComposite

# 正确
BeehaveTree
└── SelectorComposite   <- 只有一个根节点
    ├── SequenceComposite
    └── SequenceComposite
```

### 错误 12【源码事实】：RepeaterDecorator 属性名

```gdscript
# 猜测的错误名
max_count / repeat_count

# 正确（源码确认）
repetitions = 3
```

### 错误 13【项目实践】：ConditionLeaf 不应依赖其他分支写入的 Blackboard 值（脏数据问题）

**这是动态 AI 里最隐蔽的 bug 来源之一。**

```
SelectorReactiveComposite
├── SequenceReactiveComposite [技能A]
│   ├── CheckInMeleeRange  <- 依赖 blackboard["player"] 判断距离
│   └── DashSlashAction
├── SequenceReactiveComposite [追击]
│   ├── CheckPlayerDetected  <- 写入 blackboard["player"]
│   └── MoveToPlayer
```

问题：`CheckInMeleeRange` 排在 `CheckPlayerDetected` 之前。前者从 blackboard 读 player，
后者才写入 player。如果玩家已跑出感知范围，`CheckPlayerDetected` 会 erase player，
但 `CheckInMeleeRange` 先执行，读到的是**上一帧留下的旧 player**，距离判断可能仍然为 SUCCESS，
导致技能在玩家已离开后继续触发。

**修复原则：每个 ConditionLeaf 自给自足地感知，不读其他分支写入的 blackboard 数据。**

```gdscript
# 错误：依赖其他分支写入的 blackboard["player"]
func tick(actor, blackboard):
    var player = blackboard.get_value("player")   # 可能是上帧旧数据
    if player == null: return FAILURE
    return SUCCESS if dist <= range else FAILURE

# 正确：自己感知，顺手更新 blackboard
func tick(actor, blackboard):
    var players = actor.get_tree().get_nodes_in_group("player")
    if players.is_empty(): return FAILURE
    var player = players[0]
    var dist = actor.global_position.distance_to(player.global_position)
    if dist <= range:
        blackboard.set_value("player", player)   # 顺手更新，保证后续 Action 读到最新值
        return SUCCESS
    return FAILURE
```

### 错误 14【项目实践】：SelectorReactive 里高优先级分支会持续中断低优先级分支的计时

**这是错误13（CooldownDecorator 被 interrupt 重置）的同类问题，受害者是 DelayDecorator 和 TimeLimiterDecorator 的计时。**

场景：Phase3 Selector 有两个分支，A（死亡冲刺）优先级高于 B（蓄力爆炸）。

```
SelectorReactiveComposite [Phase3Selector]
├── SequenceReactiveComposite [P3ParallelSeq]  <- 优先级高
│   ├── IsPlayerDetected
│   └── SimpleParallelComposite
│       ├── TimeLimiterDecorator(3s) -> RageChaseAction   <- 主任务，3秒后超时FAILURE
│       └── ContinuousFireAction
└── SequenceReactiveComposite [P3ExplosionSeq]  <- 优先级低
    ├── IsPlayerDetected
    └── DelayDecorator(1.2s) -> AreaExplosionAction       <- 需要1.2秒才能触发
```

**实际执行流程：**
1. `P3ParallelSeq` RUNNING（冲刺中），`Phase3Selector.running_child = P3ParallelSeq`
2. 3秒后 `TimeLimiterDecorator` 超时 -> `RageParallel` FAILURE -> `P3ParallelSeq` FAILURE
3. `Phase3Selector` 继续到 `P3ExplosionSeq`，`DelayDecorator` 开始计时，返回 RUNNING
4. `Phase3Selector.running_child = P3ExplosionSeq`
5. **下一帧**，`Phase3Selector` 从头开始：`P3ParallelSeq` tick -> `IsPlayerDetected` SUCCESS -> `TimedRageChase.before_run()` 重置计时器 -> 返回 RUNNING
6. `P3ParallelSeq` 返回 RUNNING，`Phase3Selector` 立即 return RUNNING，**`P3ExplosionSeq` 被中断**，`DelayDecorator` 计时归零
7. 回到步骤1，无限循环，`AreaExplosionAction` 永远不会触发

**根本原因：** `SelectorReactiveComposite` 每帧从第一个子节点重新开始，高优先级分支只要条件满足就会抢占 running_child。低优先级分支里任何依赖时间累积的节点（`DelayDecorator`、`TimeLimiterDecorator`、手动计时器）都会在被中断时重置，永远无法完成。

**修复原则：高优先级分支完成后必须有一段自管理冷却期（返回 FAILURE），给低优先级分支留出执行窗口。冷却时长必须大于低优先级分支需要的时间。**

```gdscript
# 在高优先级分支的核心 Action 里（如 RageChaseAction），
# 被 TimeLimiterDecorator interrupt 时设置冷却：
func interrupt(actor: Node, blackboard: Blackboard) -> void:
    var actor_id := str(actor.get_instance_id())
    # 冷却 4 秒 > DelayDecorator 的 1.2 秒，爆炸有足够窗口触发
    blackboard.set_value(COOLDOWN_KEY, Time.get_ticks_msec() + cooldown * 1000, actor_id)
    actor.stop_horizontal()
    super(actor, blackboard)

func tick(actor: Node, blackboard: Blackboard) -> int:
    # 冷却中返回 FAILURE，让 Selector 跳过本分支
    if Time.get_ticks_msec() < blackboard.get_value(COOLDOWN_KEY, 0.0, actor_id):
        return FAILURE
    # ... 正常执行 ...
```

**推论：在 SelectorReactive 里，任何需要"A 完成后才触发 B"的模式，都需要 A 在完成后主动冷却一段时间。**

### 错误 15【项目实践 / 2D 横向动作项目】：ActionLeaf 里用 distance_to 判断到达位置会包含 Y 轴误判

```gdscript
# 错误：distance_to 包含 Y 轴距离
var dist = actor.global_position.distance_to(player.global_position)
if dist <= stop_distance:
    actor.stop_horizontal()
    return RUNNING  # 或 SUCCESS

# 现象：玩家站在上方平台时，斜线距离满足 stop_distance，
# 但水平距离还很远，Boss 原地停住反复抖动，无法到达玩家

# 正确：只检查水平距离
var h_dist = abs(player.global_position.x - actor.global_position.x)
if h_dist <= stop_distance:
    actor.stop_horizontal()
    return RUNNING
```

### 错误 16【通用工程事实】：GDScript.new() + source_code 动态脚本在运行时不会自动编译

```gdscript
# 错误：节点加入场景树时脚本是空的，代码不会执行
var script = GDScript.new()
script.source_code = """
extends CharacterBody2D
func _physics_process(delta):
    velocity = get_meta("velocity")
    move_and_slide()
"""
node.set_script(script)   # 脚本未编译，_physics_process 不会被调用

# 正确：用独立 .gd 文件 + preload
const BULLET_SCENE = preload("res://scenes/bullet.tscn")
var bullet = BULLET_SCENE.instantiate()
# 或者
const BulletScript = preload("res://scripts/bullet.gd")
node.set_script(BulletScript)   # preload 的脚本已编译，可以正常运行
```

### 错误 17【工程事实】：AutoLoad 未注册导致 BeehaveGlobalDebugger 找不到

```
E: Node not found: "BeehaveGlobalDebugger" (relative to "/root")
```

原因：插件启用时未正确注册 AutoLoad。

解决步骤（按顺序尝试）：
1. `Project -> Project Settings -> Plugins` -> 禁用 Beehave -> 等一秒 -> 重新启用
2. 检查 `Project -> Project Settings -> Autoload` 是否有这两条：
   - `BeehaveGlobalDebugger` -> `res://addons/beehave/debug/global_debugger.gd`
   - `BeehaveGlobalMetrics` -> `res://addons/beehave/metrics/beehave_global_metrics.gd`
3. 如果没有，手动添加，或直接在 `project.godot` 里加：
   ```ini
   [autoload]
   BeehaveGlobalDebugger="*res://addons/beehave/debug/global_debugger.gd"
   BeehaveGlobalMetrics="*res://addons/beehave/metrics/beehave_global_metrics.gd"
   ```

### 错误 18【源码事实 / T-29 实测】：SequenceReactive 非末尾位置放可返回 RUNNING 的 ActionLeaf 会导致后续 Action 永远无法运行

```gdscript
# 错误写法：ActionA 完成后，ActionB 每次只能运行 1 帧即被中断
SequenceReactiveComposite
├── ActionA (N帧后SUCCESS)   <- 完成后 before_run 每帧重置 → 永远重新返回 RUNNING
└── ActionB (永远RUNNING)    <- 每 N+1 帧被 interrupt 一次，永远无法稳定执行

# 现象：ActionB 每次 before_run+tick→RUNNING 后，下帧就收到 interrupt，循环往复
# 即使用 AlwaysSucceedDecorator 包裹 ActionA 也无法解决（T-29 场景C 确认）
```

根本原因：`SequenceReactiveComposite` 每帧对 `running_child` 之前的所有节点调用 `before_run()`。ActionA 完成后不再是 `running_child`，每帧被 `before_run()` 重置内部计数，导致每帧重新返回 RUNNING，从而 interrupt 后面的 ActionB。

```gdscript
# 正确写法：前置位置只用 ConditionLeaf（永不返回 RUNNING，不会中断后续）
SequenceReactiveComposite
├── IsReadyCondition (ConditionLeaf，返回SUCCESS/FAILURE) <- 每帧被before_run，无状态副作用→安全
└── ActionB (永远RUNNING)                                 <- 稳定运行

# 规则：SequenceReactive 中，只有最后一个节点才能是可返回 RUNNING 的 ActionLeaf
```

---

## 十一、完整节点 class_name 速查

| class_name | .tscn 中应用的脚本路径 |
|---|---|
| `BeehaveTree` | `addons/beehave/nodes/beehave_tree.gd` |
| `SequenceComposite` | `nodes/composites/sequence.gd` |
| `SequenceStarComposite` | `nodes/composites/sequence_star.gd` |
| `SequenceReactiveComposite` | `nodes/composites/sequence_reactive.gd` |
| `SelectorComposite` | `nodes/composites/selector.gd` |
| `SelectorReactiveComposite` | `nodes/composites/selector_reactive.gd` |
| `SequenceRandomComposite` | `nodes/composites/sequence_random.gd` |
| `SelectorRandomComposite` | `nodes/composites/selector_random.gd` |
| `SimpleParallelComposite` | `nodes/composites/simple_parallel.gd` |
| `InverterDecorator` | `nodes/decorators/inverter.gd` |
| `AlwaysFailDecorator` | `nodes/decorators/failer.gd` |
| `AlwaysSucceedDecorator` | `nodes/decorators/succeeder.gd` |
| `LimiterDecorator` | `nodes/decorators/limiter.gd` |
| `CooldownDecorator` | `nodes/decorators/cooldown.gd` |
| `DelayDecorator` | `nodes/decorators/delayer.gd` |
| `TimeLimiterDecorator` | `nodes/decorators/time_limiter.gd` |
| `RepeaterDecorator` | `nodes/decorators/repeater.gd` |
| `UntilFailDecorator` | `nodes/decorators/until_fail.gd` |
| `BlackboardSetAction` | `nodes/leaves/blackboard_set.gd` |
| `BlackboardEraseAction` | `nodes/leaves/blackboard_erase.gd` |
| `BlackboardHasCondition` | `nodes/leaves/blackboard_has.gd` |
| `BlackboardCompareCondition` | `nodes/leaves/blackboard_compare.gd` |
| `Blackboard` | `blackboard.gd` |

---

## 十二、常用模式速查

本节默认以 **通用模式** 为主；凡是只适用于动态优先级 AI 的写法，会直接在标题里注明。

### Guard（满足条件才执行）
```
SequenceReactiveComposite   <- 用 Reactive 保证每帧重检条件
├── IsInRangeCondition
└── AttackAction
```

### Priority Selector（动态优先级 AI）
```
SelectorReactiveComposite   <- 每帧从最高优先级重新评估
├── SkillASequence          <- 技能A（含自管理冷却）
├── SkillBSequence          <- 技能B（含自管理冷却）
├── ChaseSequence           <- 追击（永远RUNNING，Selector停在这）
└── PatrolAction            <- 兜底巡逻（永远RUNNING）
```

### Reactive Guard（条件失效时自动中断）
```
SequenceReactiveComposite
├── HasTargetCondition
└── ChaseAction
```

### NOT Condition
```
InverterDecorator
└── IsAtHomeCondition
```

### 多步骤任务（不重做已完成步骤）
```
SequenceStarComposite   <- 注意：失败时保留进度，不重置
├── OpenDoorAction
├── EnterRoomAction
└── FindTargetAction
```

### 技能冷却（静态 AI，无 SelectorReactive）
```
CooldownDecorator (wait_time=3.0)
└── CastSpellAction
```

### 技能冷却（动态优先级 AI，有 SelectorReactive）
```
# 不要用 CooldownDecorator，会被 interrupt 重置
# 在 ActionLeaf 里自管理冷却（见错误13的代码示例）
SequenceReactiveComposite
├── IsInRangeCondition
└── SkillAction   <- 内部自己管理 cooldown，存 blackboard
```

### 蓄力后执行
```
DelayDecorator (wait_time=1.2)
└── ExplosionAction
```

### 限时追击
```
TimeLimiterDecorator (wait_time=3.0)
└── ChaseAction
```

### 并行（移动同时射击）
```
SimpleParallelComposite
├── MoveToTargetAction   <- 主任务
└── ContinuousFireAction <- 后台任务
```

### 限制 Action 执行时长（LimiterDecorator 唯一正确用法）
```
# 【T-16 实测】LimiterDecorator 只对永远 RUNNING 的子节点有效
# 不能用来限制"执行次数"——子节点 SUCCESS 时计数清零
LimiterDecorator (max_count=60)   <- 最多持续 60 帧
└── ChaseAction   <- 永远返回 RUNNING 的动作

# 需要限制执行次数 -> 在 ActionLeaf 内部自管理计数，存入 Blackboard
```

---

## 十三、【项目实践】动态优先级 Boss AI 的完整结构

本节总结的是**动态优先级 Boss AI 项目里的推荐结构**，已经过实测验证，适合当前这类 Boss 设计；但它不是 Beehave 插件唯一正确的组织方式。

### 核心设计原则

1. **顶层用 SelectorReactiveComposite**，每帧重新评估所有技能优先级
2. **每个技能序列用 SequenceReactiveComposite**，保证条件每帧重检
3. **冷却全部在 ActionLeaf 内自管理**，不用 CooldownDecorator
4. **每个 ConditionLeaf 自给自足感知**，不依赖其他分支的 blackboard 写入
5. **追击 Action 永远返回 RUNNING**，到达目标后停止移动但仍返回 RUNNING，让 SelectorReactive 每帧重新评估技能是否可用
6. **兜底行为（巡逻）放最后**，永远返回 RUNNING

### 验证后的完整树结构

```
BeehaveTree
└── SelectorReactiveComposite [RootSelector]

    ├── SequenceReactiveComposite [Phase3Seq]   <- HP<30% 时才进入
    │   ├── IsHPBelowCondition (threshold=0.3)
    │   └── SelectorReactiveComposite [Phase3Selector]
    │       ├── SequenceReactiveComposite [P3ParallelSeq]
    │       │   ├── IsPlayerDetected           <- 自己感知，顺手写 blackboard
    │       │   └── SimpleParallelComposite
    │       │       ├── RageChaseAction        <- 主任务（永远RUNNING直到TimeLimiter超时）
    │       │       └── ContinuousFireAction   <- 后台任务（持续射击）
    │       ├── SequenceReactiveComposite [P3ExplosionSeq]
    │       │   ├── IsPlayerDetected
    │       │   └── AreaExplosionAction        <- 内部自管理冷却
    │       ├── SequenceReactiveComposite [P3ChaseSeq]
    │       │   ├── IsPlayerDetected
    │       │   └── MoveToPlayerAction         <- 永远RUNNING
    │       └── PatrolAction                   <- 兜底，永远RUNNING

    ├── SequenceReactiveComposite [Phase2Seq]   <- HP 30%~60%
    │   ├── IsHPBelowCondition (threshold=0.6)
    │   └── SelectorReactiveComposite [Phase2Selector]
    │       ├── SequenceReactiveComposite [P2MeleeSeq]
    │       │   ├── IsPlayerInMeleeRange       <- 自己感知，不依赖 blackboard
    │       │   └── DashSlashAction            <- 内部自管理冷却
    │       ├── SequenceReactiveComposite [P2BarrageSeq]
    │       │   ├── IsPlayerDetected
    │       │   └── BurstBarrageAction         <- 内部自管理冷却
    │       ├── SequenceReactiveComposite [P2SummonSeq]
    │       │   ├── IsPlayerDetected
    │       │   └── SummonMinionAction         <- 内部自管理冷却+次数限制
    │       ├── SequenceReactiveComposite [P2ChaseSeq]
    │       │   ├── IsPlayerDetected
    │       │   └── MoveToPlayerAction
    │       └── PatrolAction

    └── SelectorReactiveComposite [Phase1Selector]   <- 默认阶段
        ├── SequenceReactiveComposite [P1MeleeSeq]
        │   ├── IsPlayerInMeleeRange (自给自足感知)
        │   └── DashSlashAction (自管理冷却)
        ├── SequenceReactiveComposite [P1RangeSeq]
        │   ├── IsPlayerDetected
        │   ├── InverterDecorator -> IsPlayerInMeleeRange  <- NOT 近战
        │   └── FireBurstAction (自管理冷却)
        ├── SequenceReactiveComposite [P1ChaseSeq]
        │   ├── IsPlayerDetected              <- 玩家离开感知范围时 FAILURE，回到巡逻
        │   └── MoveToPlayerAction            <- 到达后停止但持续 RUNNING
        └── PatrolAction                      <- 永远 RUNNING，SelectorReactive 稳定在此
```

### 追击 Action 的正确写法

```gdscript
# 关键：到达目标后不返回 SUCCESS，而是停止移动继续 RUNNING
# SelectorReactive 每帧重新从技能分支开始评估，冷却结束后技能会被优先触发
func tick(actor: Node, blackboard: Blackboard) -> int:
    var player = blackboard.get_value("player")
    if player == null:
        return FAILURE

    var h_dist = abs(player.global_position.x - actor.global_position.x)  # 只看水平距离！
    if h_dist <= stop_distance:
        actor.stop_horizontal()
        return RUNNING  # 不返回 SUCCESS，维持 RUNNING 让 Selector 稳定在此

    var dir_x = sign(player.global_position.x - actor.global_position.x)
    actor.velocity.x = dir_x * move_speed
    return RUNNING
```

### 技能冷却的正确写法

```gdscript
class_name MySkillAction extends ActionLeaf

@export var cooldown: float = 3.0
const COOLDOWN_KEY = "cooldown_my_skill"

func tick(actor: Node, blackboard: Blackboard) -> int:
    var actor_id := str(actor.get_instance_id())
    # 检查冷却
    if Time.get_ticks_msec() < blackboard.get_value(COOLDOWN_KEY, 0.0, actor_id):
        return FAILURE

    # ... 执行技能（可以是多帧的状态机）...

    # 技能完成后设置冷却
    blackboard.set_value(COOLDOWN_KEY, Time.get_ticks_msec() + cooldown * 1000, actor_id)
    return SUCCESS

func interrupt(actor: Node, blackboard: Blackboard) -> void:
    # 不清除 COOLDOWN_KEY！让冷却保持
    # 只清理技能内部状态
    _reset_internal_state()
    super(actor, blackboard)
```

### 调试方法

当 Boss 行为异常时，在关键 ConditionLeaf 和 ActionLeaf 里加临时 print：

```gdscript
# 在 ConditionLeaf.tick 里
print("[Detect] dist=%.1f -> %s, name=%s" % [dist, "SUCCESS" if result==SUCCESS else "FAILURE", name])

# 在 ActionLeaf.interrupt 里
print("[%s] interrupt called" % name)
```

观察规律：
- 某个 ConditionLeaf 一直在打印 SUCCESS 但对应 Action 没执行 -> 该 Action 被上面优先级更高的分支占据 running_child
- 某个 ActionLeaf 的 interrupt 被频繁调用 -> SelectorReactive 在频繁切换分支，检查是否有 CooldownDecorator 被重置
- CheckPlayerXxx 消失几十帧后突然回来 -> 有其他 Sequence 占据了 running_child（通常是冷却异常导致的）


---

*文档来源：官方源码直接提取（beehave-godot-4.x branch）+ Boss AI 实战项目完整验证*
*Beehave 版本：2.9.2*
*Godot 版本：4.5.x*
*最后更新：2026-03-10*

---

## 附录 A：实测禁用规则（D-01 至 D-16）

基于 T-01 至 T-29 全量实测整理。**D-05 已根据 T-17 实测正式撤销。**

| 编号 | 状态 | 规则名称 | 说明 |
|---|---|---|---|
| D-01 | ✅ 有效 | 禁止 CooldownDecorator + Reactive 路径 | CooldownDecorator 挂在 Reactive 子树时，分支每次切换都触发 interrupt 清零冷却，导致永远无法冷却（T-04）|
| D-02 | ✅ 有效 | 禁止 DelayDecorator 在可被 interrupt 的路径下做计时 | interrupt 清零计时器，每帧被打断则永远无法完成计时（T-05）|
| D-03 | ✅ 有效 | 禁止依赖 SequenceStar 在外部 interrupt 后保留断点 | 外部 interrupt() 清零 successful_index，只有内部子节点 FAILURE 才保留（T-02/T-03/T-28）|
| D-04 | ✅ 有效 | interrupt() 实现必须幂等 | 同一节点同一帧可能收到两次 interrupt()（系统性 bug，T-11/T-28）。不能假设自身为 RUNNING，必须能安全多次调用 |
| D-05 | ❌ 已撤销 | ~~禁止依赖 RepeaterDecorator.repetitions 精确控次~~ | T-09 测试设计有误。T-17 实测确认：repetitions=N 完全有效，子节点成功 N 次后正确返回 SUCCESS |
| D-06 | ✅ 有效 | 禁止将 SimpleParallel.secondary_repeat_count 视为全局总次数 | 该计数在每次 before_run 时重置，是每轮局部上限，不是全局累积（T-07）|
| D-07 | ✅ 有效 | 禁止 UntilFail 包裹永远 RUNNING 的节点放在 Selector 中 | UntilFail 永远返回 RUNNING，Selector 后续分支饿死（T-08）|
| D-08 | ✅ 有效 | 禁止 delay_mode=true 的副任务中包含可能永远 RUNNING 的节点 | 主任务结束后等待副任务完成，副任务永远 RUNNING 导致整棵树卡死（T-06）|
| D-09 | ✅ 有效 | 禁止高优先级分支 Condition 设计为永久 SUCCESS | SelectorReactive 中低优先级分支永远被 interrupt，无法执行（T-14）|
| D-10 | ✅ 有效 | 禁止 TimeLimiter + SequenceStar 期望断点续传 | TimeLimiter 超时触发 interrupt，清零 SequenceStar.successful_index（T-15）|
| D-11 | ✅ 有效 | 禁止在程序构建的动态树中使用 BlackboardCompareCondition | 表达式字段只能 Inspector 手动填写，无法 GDScript 赋值（T-12）|
| D-12 | ✅ 有效 | 禁止在永远立即 SUCCESS 的 Action 中依赖 before_run 做初始化 | 立即 SUCCESS 后树根 status=SUCCESS，下帧重入跳过 before_run（T-13）|
| D-13 | ✅ 有效 | 禁止用 LimiterDecorator 限制 Action 执行次数 | 只对子节点持续 RUNNING 有效；子节点返回非 RUNNING 时计数清零（T-16）|
| D-14 | ✅ 有效 | 禁止依赖 tree.enabled=false/true 重置行为树状态 | re-enable 后 BeehaveTree.status 不清零，before_run 永久丢失（T-18）|
| D-15 | ✅ 有效 | 禁止在 SelectorReactive 路径下依赖 TimeLimiterDecorator 超时 | interrupt() 重置计时器，分支切换时永远归零，TimeLimiter 无法累积到 wait_time（T-24，源码确认）|
| D-16 | ✅ 有效 | 禁止在 SequenceReactive 非末尾位置放可返回 RUNNING 的 ActionLeaf | ActionLeaf 完成后每帧被 before_run 重置，每帧重新返回 RUNNING，永远中断后续 Action（T-29）|

---

## 附录 B：T-01 至 T-29 测试结论汇总

| 编号 | 结论 | 核心发现 |
|---|---|---|
| T-01 | ✅ | after_run 与 tick→SUCCESS/FAILURE 完全同帧调用 |
| T-02 | ⚠️ | 外部 interrupt() 后 SequenceStar 与 Sequence 行为一致，successful_index 不保留 |
| T-03 | ✅ | interrupt 后 last_execution_index 正确重置；interrupt() 不能假设节点为 RUNNING |
| T-04 | ❌ | CooldownDecorator + Reactive：Cooldown 被无限清零，产生 D-01 禁用规则 |
| T-05 | ✅ | DelayDecorator 被 interrupt 后计时从零重新开始，产生 D-02 |
| T-06 | ✅ | delay_mode=true 副任务 SUCCESS 后树卡死；delay_mode=false 立即重入 |
| T-07 | ❌ | secondary_repeat_count 是每轮局部计数，每次 before_run 重置，产生 D-06 |
| T-08 | ✅ | UntilFail 正确卡住 Selector，兜底分支永远未执行 |
| T-09 | ❌→撤销 | 测试设计有误，T-17 确认 Repeater 正常，D-05 撤销 |
| T-10 | ✅ | SequenceReactive：Condition 变 FAILURE 同帧 Action.interrupt 被调用 |
| T-11 | ✅ | SelectorReactive 高优先级抢占同帧 interrupt；双重 interrupt 系统性 bug 确认 |
| T-12 | ⚠️ 跳过 | BlackboardCompareCondition 表达式字段只能 Inspector 手动填写，产生 D-11 |
| T-13 | ❌ | 永远立即 SUCCESS 的 Action 从第2次起 before_run 不再调用，产生 D-12 |
| T-14 | ✅ | 高优先级永久 SUCCESS 导致低优先级饿死；CooldownDecorator 被 interrupt 清零 |
| T-15 | ❌ | TimeLimiter + SequenceStar：超时后 successful_index 不保留，产生 D-10 |
| T-16 | ❌ | LimiterDecorator 语义与文档相反：只限 RUNNING 帧数，不限执行次数，产生 D-13 |
| T-17 | ✅ | RepeaterDecorator.repetitions 完全有效，D-05 正式撤销 |
| T-18 | ❌ | tree.enabled=false 触发 interrupt 正确；re-enable 后 before_run 永久丢失，产生 D-14 |
| T-19 | ✅ | tick_rate 跳帧正确；Condition 响应延迟最多 tick_rate-1 帧 |
| T-20 | ✅/❌ | 共享 BB + default 命名空间完全污染（❌）；actor-id 命名空间完全隔离（✅）|
| T-21 | ✅ | SelectorComposite 非 Reactive：RUNNING 期间 Condition 完全不重评估 |
| T-22 | ❌→纠正 | SelectorReactive 下 running_child 之后的子节点每帧被调用 before_run，即使从未 tick |
| T-23 | ✅ | InverterDecorator：RUNNING 原样透传；interrupt 正确穿透；SUCCESS/FAILURE 正确反转 |
| T-24 | ⚠️ | TimeLimiter 基本功能正常（超时/interrupt重置/before_run重置均正确）；SelectorReactive 路径下 interrupt 清零计时 → 永远无法超时，产生 D-15 |
| T-25 | ✅ | AlwaysSucceed/Fail 正确转换状态；interrupt 传递链穿透装饰器；child 成为 running_child 后停止调用 before_run，无泄漏 |
| T-26 | ✅ | SequenceRandom 每帧洗牌；resume_on_failure = 跳过已处理节点非重试；SelectorRandom 遇第一个 SUCCESS 立即停止 |
| T-27 | ✅ | SimpleParallel delay_mode=false 同帧 interrupt；delay_mode=true 等 secondary 完成当前整轮；repeat_count=1 只跑1次后 primary 独自运行 |
| T-28 | ✅ | SequenceStar 内部 FAILURE 保留 successful_index（跳过已成功节点）；外部 interrupt 清零；双重 interrupt bug 再次确认 |
| T-29 | ❌ | SequenceReactive 前置 ActionLeaf 致命陷阱：后续 Action 永远只能运行1帧；AlwaysSucceed 包裹无效；正确解法：前置只用 ConditionLeaf，产生 D-16 |

---

## 附录 C：系统性 Bug（Beehave 2.9.2）

以下 bug 在多个测试中复现，属于 Beehave 2.9.2 的系统性缺陷：

**1. 双重 interrupt（T-02/T-03/T-11/T-15）**
同一节点同一帧可能收到两次 `interrupt()` 调用。所有自定义节点的 `interrupt()` 实现必须幂等（D-04）。

**2. before_run 丢失（T-13）**
永远立即 SUCCESS 的 Action 从第2次进入起 before_run 不再被调用。`BeehaveTree` 仅在 `status != RUNNING` 时调用 before_run，立即 SUCCESS 导致状态循环中跳过（D-12）。

**3. re-enable 状态不重置（T-18）**
`tree.enabled=false` 触发 interrupt 正确，但 `enabled=true` 后 `BeehaveTree.status` 不清零，before_run 永久丢失（D-14）。

**4. SelectorReactive before_run 泄漏（T-22）**
`SelectorReactive` 每帧对所有非 `running_child` 的子节点调用 `before_run`，即使这些节点从未被 tick。before_run 中的副作用初始化逻辑会被每帧触发。

`SequenceReactive` 存在相同机制（T-29 场景 A）：前置 ConditionLeaf 每帧被调用 before_run。ConditionLeaf 本身无状态副作用，故安全；但若前置节点是 ActionLeaf，则每帧 before_run 重置其内部计数，引发 D-16 陷阱。

**5. SequenceReactive 前置 ActionLeaf 无限中断（T-29）**
`SequenceReactive` 中，当前置 ActionLeaf 完成（返回 SUCCESS）后，下帧起该节点不再是 `running_child`，每帧被 `before_run()` 重置 → 每帧重新返回 RUNNING → 后续 Action 每帧被 `interrupt()`，永远只能执行1帧。`AlwaysSucceedDecorator` 包裹无效（T-29 场景 C）。工程规避方案：SequenceReactive 的非末尾位置只放 ConditionLeaf（D-16）。
