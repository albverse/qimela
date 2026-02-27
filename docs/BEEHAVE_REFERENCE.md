# Beehave 2.9.x 完整参考文档（基于官方源码 + 实战校对）

> 适用版本：Beehave 2.9.2 / Godot 4.5.x
> 本文档直接从官方源码提取并经实战项目完整验证，已修正多处理论错误

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

**所有 Beehave 内置节点对应的脚本路径：**

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
| `tick_rate` | int | 1 | 每 N 帧执行一次（1 = 每帧） |
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

**跨帧行为（源码确认）：**
- 内部用 `successful_index` 跟踪进度，跳过已成功的节点
- 遇到 RUNNING：记录位置，下帧从此处继续
- 遇到 FAILURE：**`successful_index` 重置为 0**，下帧从头开始
- 全部 SUCCESS 后：`successful_index` 重置为 0，返回 SUCCESS

> SequenceComposite 不适合作为技能序列放在 SelectorReactive 下。
> successful_index 的推进会导致条件节点被跳过（见错误13）。
> 技能序列需要每帧重新检查条件，应使用 SequenceReactiveComposite。

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

```
# 用途：条件失效时自动中断正在执行的 Action
SequenceReactiveComposite
├── CanSeePlayerCondition   <- 每帧重新检查，失效则中断下面的 Action
└── ChaseAction
```

> **与 SequenceComposite 的选择：**
> - 技能序列（条件+冷却+Action） -> 用 **SequenceReactiveComposite**，保证每帧重新检查条件
> - 静态多步骤任务（不需要每帧重检条件） -> 可用 SequenceComposite 或 SequenceStarComposite

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

**在动态优先级 AI 里是主力 Selector**，配合 SequenceReactiveComposite 使用。

### 7.6 SequenceRandomComposite

子节点随机排序后执行。额外属性：`random_seed`、`use_weights`、`resume_on_failure`、`resume_on_interrupt`。信号：`reset(new_order)`。

### 7.7 SelectorRandomComposite

子节点随机排序后尝试。额外属性同上（无 resume 选项）。

### 7.8 SimpleParallelComposite

**必须恰好 2 个子节点**。主任务（index 0）决定整体结果，后台任务（index 1）持续执行且结果被忽略。

Inspector 属性：
- `secondary_node_repeat_count`：后台任务重复次数（0 = 无限循环）
- `delay_mode`：true = 主任务结束后等后台任务完成当前 Action 再结束

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

子节点最多被 tick `max_count` 次，超过后返回 FAILURE。

> **`max_count` 默认值为 0（源码第11行）**：`current_count < max_count` 的判断在 max_count=0 时第一次 tick 就直接进入 FAILURE 分支。**使用时必须手动设置 max_count >= 1**，否则等同于"禁用"该节点（立即失败）。

Inspector 属性：
- `max_count`：最大 tick 次数（**必须 >= 1，默认 0 = 立即失败**）

计数存储在 Blackboard 中（带 actor 命名空间），子节点返回非 RUNNING 时自动重置，`interrupt()` 也会重置。

### 8.5 CooldownDecorator

子节点执行完（非 RUNNING）后，在 `wait_time` 秒内直接返回 FAILURE。

- `wait_time`：冷却时间（float，秒）
- 用 `Time.get_ticks_msec()` 计算（2.9.0 修复了此前用物理帧计算的 Bug）
- **`interrupt()` 时冷却时间重置为 0**

> **严重陷阱（实战验证）：CooldownDecorator 在动态优先级 AI 里几乎无法正常使用。**
>
> 在 `SelectorReactiveComposite` + `SequenceReactiveComposite` 的结构里，任何分支切换都会触发 `interrupt()`，而 `interrupt()` 会把冷却时间重置为 0。
>
> **实际发生的情况：**
> 1. 远程攻击技能执行完，`CooldownDecorator` 开始 3 秒冷却
> 2. 下一帧近战技能触发，`SelectorReactive` 切换 running_child
> 3. `_interrupt_children()` 被调用 -> `CooldownDecorator.interrupt()` -> **冷却归零**
> 4. 下一帧远程序列重新执行，冷却已清除，又立刻开火
> 5. 这反过来又触发切换 -> 冷却再次归零 -> 无限循环
>
> **调试方法**：如果 Boss 的某个技能序列被异常频繁触发，且其他行为（追击/巡逻）消失，
> 很可能就是 CooldownDecorator 被反复 interrupt 重置导致的。
> 通过在 ConditionLeaf 加 `print` 输出观察哪些节点在执行，可快速定位。
>
> **正确替代方案：在 ActionLeaf 内自管理冷却。**
>
> ```gdscript
> # 在 ActionLeaf 里自己管理冷却，存在 blackboard，interrupt 不会影响它
> const COOLDOWN_KEY = "cooldown_my_skill"
>
> func tick(actor: Node, blackboard: Blackboard) -> int:
>     var actor_id := str(actor.get_instance_id())
>     var end_time: float = blackboard.get_value(COOLDOWN_KEY, 0.0, actor_id)
>     if Time.get_ticks_msec() < end_time:
>         return FAILURE   # 冷却中，让 Sequence 失败，Selector 往下走
>
>     # ... 执行技能逻辑 ...
>
>     # 技能完成后才设置冷却（不在 before_run 或 interrupt 里清除）
>     blackboard.set_value(COOLDOWN_KEY, Time.get_ticks_msec() + cooldown * 1000, actor_id)
>     return SUCCESS
>
> func interrupt(actor: Node, blackboard: Blackboard) -> void:
>     # 不清除 COOLDOWN_KEY，让冷却自然等待
>     super(actor, blackboard)
> ```
>
> **CooldownDecorator 仅适用于：** 静态 AI（没有 SelectorReactive 动态切分支）或者不会被 interrupt 打断的固定序列。

### 8.6 DelayDecorator

**执行前**等待 `wait_time` 秒，等待期间返回 RUNNING，之后才执行子节点。

- `interrupt()` 时计时重置
- 用 `get_physics_process_delta_time()` 累积

### 8.7 TimeLimiterDecorator

给子节点设定**最大运行时间**，超时后中断并返回 FAILURE。

- `before_run()` 时重置计时器
- `interrupt()` 时重置

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

### 错误 1：.tscn 场景文件中不能用 class_name 作为 type

```
# 错误 报错：Cannot get class 'BeehaveTree'
[node name="BeehaveTree" type="BeehaveTree" parent="."]

# 正确
[node name="BeehaveTree" type="Node" parent="."]
script = ExtResource("bt_tree")
```

所有 Beehave 内置节点和自定义叶节点都适用此规则。详见文档开头的路径对照表。

### 错误 2：Blackboard 方法名

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

### 错误 3：内置 Blackboard 节点的表达式中不能用 blackboard 变量名

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

### 错误 4：SequenceComposite 和 SequenceStarComposite 的根本差异

```
SequenceComposite：FAILURE 后 successful_index 重置为 0，下次从头开始
SequenceStarComposite：FAILURE 后 successful_index 保留，下次跳过已成功的节点

# 用条件+行为组合时用 SequenceComposite 或 SequenceReactiveComposite
# 用多步骤任务且不想重做已完成步骤时用 SequenceStarComposite
```

### 错误 5：LimiterDecorator 默认 max_count = 0 等于立即失败

```gdscript
# 源码：if current_count < max_count -> 执行子节点
# max_count = 0 时条件永远为假，第一次 tick 直接返回 FAILURE

# 使用时必须设置
max_count = 3   # 至少为 1
```

### 错误 6：AlwaysSucceedDecorator 和 AlwaysFailDecorator 不覆盖 RUNNING

```gdscript
# 子节点 RUNNING 时，两者都直接返回 RUNNING
# 不能用来"把 RUNNING 变成 SUCCESS/FAILURE"

# 想让 Selector 停在某个 RUNNING 分支？
# -> 不需要任何装饰器，Selector 遇到 RUNNING 本身就会停留
```

### 错误 7：三个时间装饰节点区别

| 节点 | 时机 | 等待期返回 | 触发结果 |
|---|---|---|---|
| `DelayDecorator` | **执行前**等待 N 秒 | RUNNING | 等完才执行子节点 |
| `CooldownDecorator` | **执行后**冷却 N 秒 | — | 冷却中直接 FAILURE |
| `TimeLimiterDecorator` | **执行中**限制总时长 | — | 超时中断返回 FAILURE |

### 错误 8：MANUAL 模式会强制将 enabled 置为 false

```gdscript
# 源码（beehave_tree.gd:47）：
self.enabled = self.enabled and process_thread != ProcessThread.MANUAL

# 切到 MANUAL 后：
# - enabled 被强制设为 false
# - 在 Inspector 重新勾选 enabled 也不会自动 tick
# - 只能用代码：tree.tick()
# - 若要恢复自动，需先改回 process_thread = PHYSICS/IDLE，再 tree.enable()
```

### 错误 9：SimpleParallelComposite 必须恰好 2 个子节点

不是"至少 2 个"，多或少都有警告。

### 错误 10：重写 interrupt() 必须调 super()

```gdscript
func interrupt(actor: Node, blackboard: Blackboard) -> void:
    my_cleanup()
    super(actor, blackboard)   # 必须！否则调试器消息丢失
```

### 错误 11：BeehaveTree 只能有一个直接子节点

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

### 错误 12：RepeaterDecorator 属性名

```gdscript
# 猜测的错误名
max_count / repeat_count

# 正确（源码确认）
repetitions = 3
```

### 错误 13：ConditionLeaf 不应依赖其他分支写入的 Blackboard 值（脏数据问题）

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

### 错误 14：SelectorReactive 里高优先级分支会持续中断低优先级分支的计时（实战发现）

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

### 错误 15：ActionLeaf 里用 distance_to 判断到达位置会包含 Y 轴误判（2D 游戏）

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

### 错误 16：GDScript.new() + source_code 动态脚本在运行时不会自动编译

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

### 错误 17：AutoLoad 未注册导致 BeehaveGlobalDebugger 找不到

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

### 限制召唤次数（LimiterDecorator 正确用法）
```
SequenceReactiveComposite
├── CanSummonCondition
└── LimiterDecorator (max_count=3)   <- max_count 必须 >= 1，不要在外面套 CooldownDecorator
    └── SummonAction   <- SummonAction 内部自管理冷却
```

---

## 十三、实战架构：动态优先级 Boss AI 的完整结构

本节总结经过实测验证的 Boss AI 正确结构，避免重踩所有已知陷阱。

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

## 十四、常用模式速查（完整节点 class_name 版）

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

*文档来源：官方源码直接提取（beehave-godot-4.x branch）+ Boss AI 实战项目完整验证*
*Beehave 版本：2.9.2*
*Godot 版本：4.5.x*
*最后更新：2026-02-27*
