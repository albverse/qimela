# Spine-Godot 最新方法整合规范（Godot 4.5+ / 2026-02-08）

> **目的**：把「官方 spine-godot 最新用法」与项目内《SPINE_GODOT_API_STANDARD.md》的工程经验合并成一套可执行标准，降低“签名差异 / 信号不触发 / 坐标系翻车 / 动画卡死”的概率。  
> **适用**：Godot 4.x（当前项目：4.5.1）+ spine-godot（GDExtension 或 engine module）  
> **重要声明**：本文覆盖的是“项目必用/高频方法”，**不是穷举 API**；遇到未收录方法，必须回到官方文档核对后再使用。

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
`animation_*` 信号可能因为：动画被打断、场景重载导致连接丢失、update mode 配置错误等原因“看似不触发”。  
**项目规则：信号 + 轮询（poll）双保险，FSM 不允许只靠信号推进。**

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
DOC_CHECK: spine-godot Runtime Documentation 已核对（2026-02-08）
EXPECTED: set_animation(animation_name, loop, track) 但保留探测兼容
```

### 3.3 本项目当前落地约定（2026-02）
- **唯一 Spine API 门面：`PlayerAnimator`**。上层玩法（Player/ChainSystem/ActionFSM）不得直接调用 `SpineSprite` 或 `SpineAnimationState`。
- `AnimDriverSpine` 仅作为 `PlayerAnimator` 的内部驱动实现，不对玩法层暴露。
- 锁链发射动画触发统一从 `PlayerChainSystem.fire()` 进入，再由 `PlayerAnimator.play_chain_fire()` 播放，避免“输入层 + 状态层”双入口漂移。
- 锁链锚点语义固定为 `chain_anchor_r/l`，不再使用“朝向翻转时左右骨骼交换”的历史方案。
- 死亡态动画裁决：`Die` 必须抢占 locomotion 与手动 chain 触发，避免在死亡帧被 `jump_*` 或 `chain_*` 覆盖。


### 3.4 项目对齐状态（2026-02-09）
- `AnimDriverSpine.setup()` 已执行初始化 6 项检查中的关键项，并新增 **Update Mode 检查**：当检测为 Manual 时，在每帧 `_physics_process` 主动调用 `update_skeleton()/updateSkeleton()`。
- `AnimDriverSpine` 已补全适配层最小职责：`setup/play/queue/stop/stop_all/get_bone_world_position`。
- Spine 方法调用已按 snake/camel 双风格做 `has_method()` 兼容（包含 `get_animation_state/getAnimationState`、`set_animation/setAnimation` 等）。

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
- `animation_interrupted(track_entry)`：动画被打断（同轨道切新动画、清轨等）。
- `animation_completed(track_entry)`：**一次 loop 完成**触发。  
  - **注意**：loop 动画会周期性触发，不要把它当作“结束”。
- `animation_ended(track_entry)`：该 entry 不会再被应用（更接近“真正结束”）。
- `animation_disposed(track_entry)`：entry 被内部回收/释放。
- `animation_event(track_entry, event)`：Spine 事件时间点回调（可做音效、打点等）。

> **项目硬规则**：信号只做“加速”，轮询负责“兜底”；不允许状态机只靠信号推进。

---

### 4.2 SpineAnimationState（AS）

#### AS.set_animation(...)
- **作用**：在指定轨道上“立刻切换并播放”某动画，返回 **TE**。
- **签名差异（必须适配）**：
  - 可能是：`set_animation(animation_name, loop, track)`
  - 也可能是：`set_animation(track, animation_name, loop)`
- **常见坑**：参数顺序错会直接报类型错误，或“看似没播放”。

#### AS.add_animation(...)
- **作用**：把动画排到队列里，前一个播放结束后自动接上，返回 **TE**。
- **常见形式**：`add_animation(animation_name, delay_seconds, loop, track)`  
  （具体顺序以官方文档与签名探测为准）

#### AS.get_current(track) / AS.getCurrent(track)
- **作用**：获取某轨道当前正在播放的 **TE**（可能为 null）。
- **用途**：轮询检测“是否完成”、读取当前动画名等。

#### AS.clear_track(track) / AS.clearTrack(track)
- **作用**：立即清空指定轨道。
- **副作用**：骨架会“停在最后姿势”（常见“停在最后一帧”来源）。
- **项目规则**：**动作层（常用 track1）不推荐用它作为停止方式。**

#### AS.clear_tracks() / AS.clearTracks()
- **作用**：立即清空所有轨道。

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
- 优先用 `.skel`（二进制），更小更快；如果用 JSON，扩展名建议 `.spine-json`（避免被当普通 json）。  
- `.atlas` 与贴图必须配套，导入后生成 `SkeletonData` 资源再赋给 SS。  
- 若出现 `get_animation_state()==null`：先排查导入链路与资源绑定。

---

## 9. 强制规则总结（可直接贴到项目 README）
1) **必须做 Doc-Check**：官方文档核对 + 本规范核对  
2) **必须做签名探测**：禁止硬编码参数顺序  
3) **必须做命名兼容**：snake/camel 都要兼容  
4) **必须做轮询兜底**：信号不作为唯一真相  
5) **动作层停止用 empty 混出**：避免停在最后一帧  
6) **骨骼坐标要验证坐标系**：优先 Godot 空间接口；必要时 Y 取负

---

## 附：原始项目文档整合来源
- `/mnt/data/SPINE_GODOT_API_STANDARD.md`（项目经验版；已在本文中纠偏与补强）

