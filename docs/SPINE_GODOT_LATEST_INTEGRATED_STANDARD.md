# Spine-Godot 最新方法整合规范（Godot 4.5+ / 2026-03-08）

> **目的**：把「官方 spine-godot 最新用法」与项目内《SPINE_GODOT_API_STANDARD.md》的工程经验合并成一套可执行标准，降低”签名差异 / 信号不触发 / 坐标系翻车 / 动画卡死 / **动画切换残帧**”的概率。
> **适用**：Godot 4.x（当前项目：4.5.1）+ spine-godot（GDExtension 或 engine module）
> **重要声明**：本文覆盖的是”项目必用/高频方法”，**不是穷举 API**；遇到未收录方法，必须回到官方文档核对后再使用。

---

## 0. 真理来源与强制核对协议（Doc-Check）

### 0.1 只认官方“最新写法”的入口（必须能打开）
- spine-godot Runtime Documentation（主手册）：https://en.esotericsoftware.com/spine-godot  
- Spine Runtimes Guide（通用概念）：https://en.esotericsoftware.com/spine-using-runtimes/  
- Spine API Reference（语义查询）：https://en.esotericsoftware.com/spine-api-reference

### 0.2 强制规则：写 Spine 代码前先做 30 秒核对
**当你准备调用任意 Spine 相关方法时（尤其是动画播放/轨道/事件/骨骼坐标）：**
1) 在官方文档页（上面链接）搜索该方法名，确认“方法是否存在 + 参数顺序 + 语义”。  
2) 在本规范（本文）对应章节核对“项目约束/坑点”。  
3) 若任一处不一致：以官方文档为准，同时更新本项目适配层（见 2 章）。

> 这条不是形式主义：spine-godot 存在分支与历史版本差异，**最容易炸的是参数顺序与命名风格**。

---

## 1. 术语与官方缩写（建议在注释与文档里统一使用）

| 缩写 | 含义 | 备注 |
|---|---|---|
| **SS** | `SpineSprite` | 场景中主节点 |
| **AS** | `SpineAnimationState` | `SS.get_animation_state()` 获取 |
| **SK** | `SpineSkeleton` | `SS.get_skeleton()` 获取 |
| **TE** | `SpineTrackEntry` | `set_animation/add_animation` 返回；**不要长期持有** |
| **BN** | `SpineBone` | `SK.find_bone()` 返回 |
| **TR** | Track（轨道） | 通常以 `0,1,2...` 表示；0 常用于基础动作 |

---

## 2. 三个“必须先搞清楚”的大坑（整合后的结论）

### 2.1 API 签名不统一（最危险）
**现状**：不同版本/分支可能出现不同签名。  
**当前官方文档示例**偏向：`set_animation(animation_name, loop, track)`。  
但历史/第三方也可能出现：`set_animation(track, animation_name, loop)`。

**项目规则：永远不假设签名。必须在初始化时探测，并通过适配层统一调用。**

### 2.2 命名风格不统一（snake_case vs camelCase）
不同版本可能同时存在：
- `get_animation_state()` vs `getAnimationState()`
- `set_animation()` vs `setAnimation()`
- `get_current()` vs `getCurrent()`
- `is_complete()` vs `isComplete()`
- `get_track_index()` vs `getTrackIndex()`
- `get_animation()` vs `getAnimation()`
- `get_name()` vs `getName()`

**项目规则：任何 Spine 对象方法调用，都必须 `has_method()` 检查再调用。**

### 2.3 信号不可靠（必须双保险）
`animation_*` 信号可能因为：动画被打断、场景重载导致连接丢失、update mode 配置错误等原因”看似不触发”。
**项目规则：信号 + 轮询（poll）双保险，FSM 不允许只靠信号推进。**

### 2.4 clearTrack / clearTracks 会冻结姿势（极易踩坑，已反复出错）

> **2026-03-08 紧急补充**：此问题已导致修女蛇（ChimeraNunSnake）动画切换残帧 bug，
> 且影响范围覆盖所有使用 `REPLACE_TRACK` 模式的实体。此条为 **最高优先级禁区**。

**官方明确说明（Spine 官方论坛 + 文档）：**

1. **`clearTrack()` / `clearTracks()` 不会把骨架恢复到初始姿势。**
   调用后，骨架会 **保持当前姿势**（冻结在上一动画最后一帧），不会自动回到 setup pose。

2. **如果要把动画混回 setup pose，应使用：**
   - `setEmptyAnimation(track, mixDuration)` — 混出到空（推荐，平滑过渡）
   - `addEmptyAnimation(track, mixDuration, delay)` — 排队混出
   - `setToSetupPose()` — 硬重置到 setup pose（立即生效，无混合）

3. **`set_animation()` 本身已具备替换当前轨道动画的能力。**
   无需先 `clearTrack()` 再 `set_animation()`。直接调用 `set_animation()` 就会自动替换。

**项目禁令：**
```gdscript
# ❌ 绝对禁止：clear_track + set_animation 连续调用
anim_state.clear_track(0)
anim_state.set_animation(“new_anim”, true, 0)
# 后果：骨架冻结在上一动画最后一帧，新动画从冻结姿势混入，产生残帧/残影

# ✅ 正确：直接 set_animation 替换
anim_state.set_animation(“new_anim”, true, 0)
# set_animation 自动处理旧动画的替换，无需手动 clear

# ✅ 正确：需要停止某轨道时，用 set_empty_animation
anim_state.set_empty_animation(track, 0.0)  # mix=0 立即清空
# 或
anim_state.set_empty_animation(track, 0.1)  # mix=0.1 平滑淡出
```

**受影响的实体（2026-03-08 已修复）：**
- ChimeraNunSnake（修女蛇）— 所有过渡动画链路
- StoneEyeBug（石眼虫）
- StoneMaskBird（石面鸟）
- Mollusc（软体怪）
- ChimeraGhostHandL（幽灵手）
- Player（玩家 EXCLUSIVE 模式）

### 2.5 animation_completed vs animation_ended 语义区别（容易混淆）

> **2026-03-08 补充**：之前项目错误地将 `animation_ended` 作为主信号，已修正。

**官方明确说明：**

| 信号 | 语义 | 适用场景 |
|------|------|---------|
| `animation_completed` | **动画播放完成一次**（loop 动画每完成一圈触发一次） | 判定”动画播完” → 切换下一段 |
| `animation_ended` | **entry 不再被应用**（与 mix out、被替换、被 clear 有关） | 仅用于观测/日志 |
| `animation_interrupted` | **动画被打断**（同轨道切新动画、清轨等） | 仅用于观测/日志 |

**项目规则：**
- **主信号**必须使用 `animation_completed`（表示”动画真正播完一次”）
- `animation_ended` 仅用于观测日志，不作为状态机推进依据
- **不要**用 `animation_ended` 判定”动画播完”，其触发时机与 mix/替换/clear 有关，不等于”播到最后一帧”

```gdscript
# ❌ 错误：用 animation_ended 当”播完”信号
sprite.animation_ended.connect(_on_animation_completed)

# ✅ 正确：用 animation_completed 当”播完”信号
sprite.animation_completed.connect(_on_animation_completed)
# animation_ended 仅做观测
sprite.animation_ended.connect(_on_animation_ended_observe)
```

### 2.6 多 track 高轨覆盖低轨（分层动画陷阱）

**官方明确说明：**
在分层动画（layered animations）中，**更高的 track 会覆盖更低 track 对同一骨骼属性的效果**。

#### 2.6.1 官方定义补充（AnimationState / tracks / layering）

- `AnimationState` 的核心职责包括：
  - 随时间推进并应用动画；
  - 播放队列（`add_animation`）；
  - 动画混合（crossfade）；
  - 多轨叠加到同一 skeleton（layering）。
- `tracks` 的官方语义：动画可在不同轨道同时作用到同一 skeleton；高轨可叠加并覆盖低轨冲突部分。

#### 2.6.2 分轨叠加规则（项目落地版）

- **规则 A：高轨只覆盖“自己打了 key 的属性”**。
  - 若高轨动画未给某骨骼/槽位/属性打 key，则该部分继续沿用低轨结果。
- **规则 B：tracks 本来就是分层设计**。
  - 典型执行顺序：`track 0` 先给出基础姿势，`track 1` 再叠加并覆盖其已 keyed 的部分。
- **规则 C：想让高轨真正压住低轨，必须给目标属性打 key**。
  - 如 `aim/attack/upper_body` 未对目标骨骼或 slot 打 key，则不会出现完整上层覆盖。

#### 2.6.3 官方典型用法（部位分层）

常见结构：

- `track 0`：`idle / walk / run`（基础层）
- `track 1`：`aim / attack / blink / upper_body`（覆盖层）

示例：

```gdscript
var state = $SpineSprite.get_animation_state()

state.set_animation("run", true, 0)      # 基础层
state.set_animation("aim_gun", true, 1)  # 覆盖层
```

#### 2.6.4 限制与注意点（官方实践向）

- 当高轨之间频繁切换（例如 `track1: B -> C`）时，可能出现过渡期“dip”观感（B 影响减弱、C 影响增强的叠加过渡）。
- `additive`（加法叠加）并非普通 layering 的默认模式；它对 setup/reset 条件要求更严格，必须按资源与运行时约束单独验证。

**排查清单：**
- 如果两个动画在不同 track 且视觉表现异常，优先检查是否存在高轨压低轨
- 同一状态机的前后动画应统一使用同一 track
- 仅在确实需要叠加（如 locomotion + action overlay）时才使用多 track

### 2.7 Godot 4.5.1 已知问题备忘

| 问题 | 状态 | 应对 |
|------|------|------|
| `.json` 导入异常 | 官方已确认 issue | 使用 `.spine-json` 扩展名 |
| 下载链接异常 | 官方已知 | 走 GitHub Actions 或 GDExtension |
| GDExtension vs Engine module 行为差异 | 持续维护中 | 排查时明确标注使用的构建类型 |

---

## 3. 推荐的项目适配层（统一入口）

> 强烈建议把所有 Spine 调用封装到 `SpineApiAdapter.gd`（或同类），上层玩法只调用适配层；未来升级只改一处。

### 3.1 适配层职责（最小集合）
- `setup(ss: SpineSprite)`：校验节点、探测签名、连接信号、启动轮询
- `play(track:int, name:String, loop:bool)`：播放动画（内部做签名与命名兼容）
- `queue(track:int, name:String, delay:float, loop:bool)`：排队动画（若用到）
- `stop(track:int)`：停止轨道（动作层建议混出）
- `stop_all()`：清空全部轨道
- `get_bone_pos(bone_name:String)->Vector2`：拿到骨骼挂点（用于发射点、锁链锚点）
- （可选）`get_bone_transform_global(name)->Transform2D`：优先走“Godot 空间”接口

### 3.2 必须写在适配层文件头的版本对齐标记
```
DOC_CHECK: spine-godot Runtime Documentation 已核对（2026-03-08）
EXPECTED: set_animation(animation_name, loop, track) 但保留探测兼容
```

### 3.3 本项目当前落地约定（2026-02）
- **唯一 Spine API 门面：`PlayerAnimator`**。上层玩法（Player/ChainSystem/ActionFSM）不得直接调用 `SpineSprite` 或 `SpineAnimationState`。
- `AnimDriverSpine` 仅作为 `PlayerAnimator` 的内部驱动实现，不对玩法层暴露。
- 锁链发射动画触发统一从 `PlayerChainSystem.fire()` 进入，再由 `PlayerAnimator.play_chain_fire()` 播放，避免“输入层 + 状态层”双入口漂移。
- 锁链锚点语义固定为 `chain_anchor_r/l`，不再使用“朝向翻转时左右骨骼交换”的历史方案。
- 死亡态动画裁决：`Die` 必须抢占 locomotion 与手动 chain 触发，避免在死亡帧被 `jump_*` 或 `chain_*` 覆盖。


### 3.4 项目对齐状态（2026-03-08）
- `AnimDriverSpine.setup()` 已执行初始化 6 项检查中的关键项，并新增 **Update Mode 检查**：当检测为 Manual 时，在每帧 `_physics_process` 主动调用 `update_skeleton()/updateSkeleton()`。
- `AnimDriverSpine` 已补全适配层最小职责：`setup/play/queue/stop/stop_all/get_bone_world_position`。
- Spine 方法调用已按 snake/camel 双风格做 `has_method()` 兼容（包含 `get_animation_state/getAnimationState`、`set_animation/setAnimation` 等）。
- **2026-03-08 关键修复**：
  - `REPLACE_TRACK` 模式不再调用 `clear_track()`，直接使用 `set_animation()` 替换（修复动画切换残帧）。
  - `EXCLUSIVE` 模式改用 `set_empty_animation()` 清空其他轨道（不再用 `clear_tracks()`）。
  - `stop()` / `stop_all()` 统一使用 `set_empty_animation()` / `set_to_setup_pose()`，禁止裸 `clear_track`。
  - 主信号从 `animation_ended` 改为 `animation_completed`（官方推荐语义）。
  - 新增 `_empty_all_tracks_except()` 和 `_reset_to_setup_pose()` 辅助方法。

---

## 4. 方法目录（每个方法都标注“干什么的”）

> 说明：以下为“项目高频方法”。完整/最新列表以官方文档为准。

### 4.1 SpineSprite（SS）

#### SS.get_animation_state() / SS.getAnimationState()
- **作用**：获取动画状态机对象 **AS**，用于播放/排队/清轨。
- **常见坑**：返回 `null` 说明 SkeletonData 未正确赋值或资源导入失败。

#### SS.get_skeleton() / SS.getSkeleton()
- **作用**：获取骨架对象 **SK**，用于查骨骼、重置 setup pose 等。

#### SS.update_skeleton()
- **作用**：在 **Manual** 更新模式下，手动推进骨架与动画一帧。
- **常见坑**：若 Update Mode=Manual 且不调用，动画不会推进，表现为“信号不触发/动画不动”。

#### SS.get_update_mode()（若存在）
- **作用**：读取当前更新模式（Process / Physics / Manual）。
- **备注**：不同版本不一定提供方法；也可能仅在 Inspector 以属性形式存在。

#### SS.get_global_bone_transform(bone_name)（若存在）
- **作用**：直接以 **Godot 2D 空间** 获取指定骨骼的全局 `Transform2D`（更推荐的挂点方式）。
- **优点**：减少自己做坐标系翻转的概率。

#### SS.set_global_bone_transform(bone_name, transform)（若存在）
- **作用**：以 Godot 空间设置骨骼变换（谨慎使用，可能影响动画播放结果）。

#### SS 信号（Signals）
- `animation_started(track_entry)`：某轨道开始播放某动画时触发（用于日志/状态机同步）。
- `animation_interrupted(track_entry)`：动画被打断（同轨道切新动画、清轨等）。仅用于观测。
- `animation_completed(track_entry)`：**动画播放完成一次**。
  - **注意**：loop 动画每完成一圈触发一次，非 loop 动画播完触发一次。
  - **✅ 项目主信号**：判定”动画播完 → 切下一段”必须用此信号。
- `animation_ended(track_entry)`：该 entry 不再被应用。
  - **⚠️ 语义陷阱**：这 **不是** “动画播到最后一帧”！与 mix out、被替换、被 clear 等操作有关。
  - **🚫 项目禁令**：**禁止用作”动画播完”的判定信号**。仅做观测日志。
  - 详见 §2.5 完整说明。
- `animation_disposed(track_entry)`：entry 被内部回收/释放。
- `animation_event(track_entry, event)`：Spine 事件时间点回调（可做音效、打点等）。

> **项目硬规则**：信号只做”加速”，轮询负责”兜底”；不允许状态机只靠信号推进。

---

### 4.2 SpineAnimationState（AS）

#### AS.set_animation(...)
- **作用**：在指定轨道上“立刻切换并播放”某动画，返回 **TE**。
- **签名差异（必须适配）**：
  - 可能是：`set_animation(animation_name, loop, track)`
  - 也可能是：`set_animation(track, animation_name, loop)`
- **常见坑**：参数顺序错会直接报类型错误，或“看似没播放”。

#### AS.add_animation(...)
- **作用**：把动画排到队列里，前一个播放结束后自动接上，返回 **TE**（可继续配置本次播放，如 reverse）。
- **常见形式**：`add_animation(animation_name, delay_seconds, loop, track)`  
  （具体顺序以官方文档与签名探测为准）

#### AS.get_current(track) / AS.getCurrent(track)
- **作用**：获取某轨道当前正在播放的 **TE**（可能为 null）。
- **用途**：轮询检测“是否完成”、读取当前动画名等。

#### AS.clear_track(track) / AS.clearTrack(track)
- **作用**：立即清空指定轨道。
- **⚠️ 官方明确行为**：骨架会 **保持当前姿势（冻结在最后一帧）**，**不会**回到 setup pose。
- **🚫 项目禁令**：**禁止在切换动画前调用**。`set_animation()` 已具备替换能力。
- **🚫 项目禁令**：**禁止用作停止方式**。停止请用 `set_empty_animation(track, mix)`。
- 详见 §2.4 完整说明。

#### AS.clear_tracks() / AS.clearTracks()
- **作用**：立即清空所有轨道。
- **⚠️ 同上**：所有轨道的骨架姿势会冻结，不回 setup pose。
- **🚫 项目禁令**：停止所有轨道请用逐轨 `set_empty_animation()` + `set_to_setup_pose()`。

#### AS.set_empty_animation(track, mix) / AS.setEmptyAnimation(...)
- **作用**：把指定轨道混出到“空动画”，让姿势平滑回归（通常回 setup pose 的方向）。
- **项目规则**：**动作层停止必须优先用它（而不是 clear_track）。**

#### AS.add_empty_animation(track, mix, delay) / AS.addEmptyAnimation(...)
- **作用**：将“空动画混出”排队（适合做“播完动作 -> 淡出”）。

---

### 4.3 SpineSkeleton（SK）

#### SK.set_to_setup_pose() / SK.setToSetupPose()
- **作用**：把骨架（bones + slots）立刻重置到 setup pose（初始姿态）。

#### SK.set_slots_to_setup_pose() / SK.setSlotsToSetupPose()
- **作用**：仅重置 slots（附件/皮肤/显示部分），更轻量。

#### SK.find_bone(name) / SK.findBone(name)
- **作用**：按名字查骨骼，返回 **BN**（SpineBone）。
- **用途**：做挂点、定位、debug 骨骼数据。

---

### 4.4 SpineBone（BN）

#### BN.get_world_x()/getWorldX() + BN.get_world_y()/getWorldY()
- **作用**：获取骨骼在 Spine runtime 语义下的 world 坐标。
- **项目规则（坐标系翻转）**：当你用 world_x/world_y 作为 Godot 2D 坐标时，通常需要 **Y 取负**：
  - `Vector2(world_x, -world_y)`
- **优先级建议**：如果可用 `SS.get_global_bone_transform()`，优先用它避免手动翻转。

---

### 4.5 SpineTrackEntry（TE）【重要：不要长期持有】

#### TE.is_complete() / TE.isComplete()
- **作用**：判断该 entry 是否播放完成（常用于 poll 兜底）。
- **注意**：不同版本命名可能不同；先 `has_method()`。

#### TE.get_track_index() / TE.getTrackIndex()
- **作用**：读取该 entry 所在 track id。

#### TE.get_animation() / TE.getAnimation()
- **作用**：获取动画对象（可再取 name）。

#### TE.set_reverse(true/false)（若存在）
- **作用**：反向播放该 entry。
- **风险**：不要持有 TE；使用时“取到 -> 用 -> 丢”。

---

### 4.6 SpineAnimation（AN）

#### AN.get_name() / AN.getName()
- **作用**：获取动画名称（常用于日志与状态机识别）。

---

## 5. 初始化检查清单（必须在 setup() 里完成）

1) 校验 `ss.get_class()=="SpineSprite"`（或 `is SpineSprite`）  
2) `ss.get_animation_state()` 非 null  
3) **API 签名探测**（见 6.1）  
4) 连接必要信号（至少 completed/ended/interrupted）  
5) 启用轮询（`_physics_process`）  
6) 校验 update mode（若是 Manual：必须保证每帧调用 `update_skeleton()`）

---

## 6. 项目必须实现的两段核心代码（建议直接放进适配层）

### 6.1 更稳的签名探测（按“类型”而不是按“参数名”猜）
> 你原文按 `args[i].name` 判断 track/name；有些版本参数名可能为空。  
> 建议改成：用 `args[i].type` 判定（int vs string）。

```gdscript
func _detect_api_signature(anim_state: Object) -> int:
    # 返回：1 = (track, name, loop) ; 2 = (name, loop, track) ; -1 = unknown
    var methods: Array = anim_state.get_method_list()
    for m: Dictionary in methods:
        var method_name: String = m.get("name", "")
        if method_name != "set_animation" and method_name != "setAnimation":
            continue
        var args: Array = m.get("args", [])
        if args.size() < 3:
            continue

        var t0: int = int(args[0].get("type", -1))
        var t1: int = int(args[1].get("type", -1))
        var t2: int = int(args[2].get("type", -1))

        # Godot Variant type 常量：TYPE_INT / TYPE_STRING / TYPE_BOOL
        if t0 == TYPE_INT and t1 == TYPE_STRING and t2 == TYPE_BOOL:
            return 1
        if t0 == TYPE_STRING and t1 == TYPE_BOOL and t2 == TYPE_INT:
            return 2

    return -1
```

### 6.2 轮询兜底（TE 不持有，只存 entry_id 去重）
```gdscript
var _track_states := {}          # track_id -> { "anim":String, "loop":bool }
var _completed_entry_id := {}    # track_id -> int

func _poll(anim_state: Object) -> void:
    for track_id in _track_states.keys():
        var state: Dictionary = _track_states[track_id]
        if state.get("loop", false):
            continue

        var entry = null
        if anim_state.has_method("get_current"):
            entry = anim_state.get_current(track_id)
        elif anim_state.has_method("getCurrent"):
            entry = anim_state.getCurrent(track_id)

        if entry == null:
            continue

        var done := false
        if entry.has_method("is_complete"):
            done = entry.is_complete()
        elif entry.has_method("isComplete"):
            done = entry.isComplete()

        if not done:
            continue

        var eid: int = entry.get_instance_id()
        if _completed_entry_id.get(track_id, -1) == eid:
            continue

        _completed_entry_id[track_id] = eid
        _on_track_completed(track_id, entry)
```

---

## 7. 最小验证场景（强烈建议做成一个 Test.tscn）
目的：用 30 秒验证“签名探测 / 信号 / 轮询 / 混出 / update mode”是否正常，避免在主工程里试错。

建议内容：
1) SS update mode = Process  
2) ready 时：play idle(loop=true) -> queue attack(loop=false) -> queue empty(mix=0.2)  
3) 打印：started/completed/ended/interrupted 全部信号  
4) 同时启用 poll：当 loop=false 且 complete -> 打印“poll complete”

---

## 8. 资源导入（容易忽略但会导致 get_animation_state=null）
- 优先用 `.skel`（二进制），更小更快；如果用 JSON，**扩展名必须用 `.spine-json`**（Godot 4.5.1 存在 `.json` 导入问题，官方已确认 issue）。
- `.atlas` 与贴图必须配套，导入后生成 `SkeletonData` 资源再赋给 SS。
- 若出现 `get_animation_state()==null`：先排查导入链路与资源绑定。
- **Godot 4.5.1 注意**：排查时应明确使用的是 GDExtension 版还是 Engine module 版，两者行为可能有差异。

---

## 9. 强制规则总结（可直接贴到项目 README）
1) **必须做 Doc-Check**：官方文档核对 + 本规范核对
2) **必须做签名探测**：禁止硬编码参数顺序
3) **必须做命名兼容**：snake/camel 都要兼容
4) **必须做轮询兜底**：信号不作为唯一真相
5) **动作层停止用 empty 混出**：避免停在最后一帧
6) **骨骼坐标要验证坐标系**：优先 Godot 空间接口；必要时 Y 取负
7) **🚫 禁止 clearTrack + setAnimation 连续调用**：set_animation 自身已替换，clear 会冻结姿势（§2.4）
8) **🚫 禁止用 animation_ended 判定"动画播完"**：必须用 animation_completed（§2.5）
9) **停止轨道/全部轨道**：必须用 set_empty_animation / set_to_setup_pose，禁止裸 clear_track
10) **过渡动画→循环动画**：同 track 直接 set_animation，不 clear，不手写 timer 猜时机

---

## 附：原始项目文档整合来源
- `/mnt/data/SPINE_GODOT_API_STANDARD.md`（项目经验版；已在本文中纠偏与补强）
