# Chain System 链条系统

> 源文件: `scene/components/player_chain_system.gd`
> 类名: `PlayerChainSystem extends Node`
> 场景挂载: `Player.tscn → Components/ChainSystem`

---

## 1. 核心架构

### 1.1 双槽位设计

链条系统采用**双槽位 (Dual Slot)** 架构，玩家同时拥有两条独立链条:

| 槽位索引 | 对应手 | Line2D 路径 | 手部锚点 |
|----------|--------|-------------|----------|
| `slot 0` | 右手 R | `Chains/ChainLine0` | `Visual/HandR` 或 Spine `chain_anchor_r` |
| `slot 1` | 左手 L | `Chains/ChainLine1` | `Visual/HandL` 或 Spine `chain_anchor_l` |

**默认 `active_slot = 1`（左手优先）**——这是刻意的设计决策。发射时优先使用 `active_slot`，若该槽位忙碌则自动尝试另一个槽位。发射后系统会调用 `_switch_to_available_slot()` 自动将 `active_slot` 切换到空闲槽位，实现连续双发。

```gdscript
# player_chain_system.gd
var chains: Array[ChainSlot] = []
var active_slot: int = 1

func pick_fire_slot() -> int:
    if chains[active_slot].state == ChainState.IDLE:
        return active_slot
    var other_slot: int = 1 - active_slot
    if chains[other_slot].state == ChainState.IDLE:
        return other_slot
    return -1  # 都忙
```

### 1.2 槽位可用性属性

提供给 ActionFSM 等外部系统查询的只读属性:

```gdscript
var slot_R_available: bool:
    get: return chains[0].state == ChainState.IDLE

var slot_L_available: bool:
    get: return chains[1].state == ChainState.IDLE
```

---

## 2. 链条状态机 (ChainState)

每条链条独立维护自己的状态，两条链条可以处于不同状态。

```gdscript
enum ChainState { IDLE, FLYING, STUCK, LINKED, DISSOLVING }
```

### 状态流转图

```
         fire()
  IDLE ─────────► FLYING
                    │
          ┌─────────┼─────────────┐
          │         │             │
          ▼         ▼             ▼
       (超时)    (墙壁命中)   (实体命中, ret=1)
          │         │             │
          ▼         ▼             ▼
        STUCK     STUCK        LINKED
          │                      │
          │ hold_t>=hold_time    │ 手动取消 / 超距 / 目标失效 / 挣脱
          ▼                      ▼
      DISSOLVING ◄───────── DISSOLVING
          │
          │ burn tween 完成
          ▼
        IDLE
```

### 各状态详解

| 状态 | 说明 | 持续条件 |
|------|------|----------|
| **IDLE** | 空闲，准备发射 | 无链条实体存在 |
| **FLYING** | 链条投射物向目标移动 | `fly_t < chain_max_fly_time` 且未碰撞 |
| **STUCK** | 命中墙壁/障碍物，短暂停留 | `hold_t < hold_time`（默认 0.5 秒） |
| **LINKED** | 连接到实体（怪物/奇美拉） | 直到手动取消、超距、目标失效或挣脱 |
| **DISSOLVING** | Burn Shader 溶解动画播放中 | Tween 动画结束后回到 IDLE |

---

## 3. 为何链条绕过 ActionFSM

链条**不是**一次性动作武器，而是一个**持久化系统覆盖层 (persistent system overlay)**。具体原因:

1. **跨帧持久化**: 链条在 FLYING → STUCK → LINKED → DISSOLVING 多个状态间持续存在，横跨大量帧
2. **双链独立运行**: 两条链条可以同时处于不同状态（例如一条 LINKED、一条 FLYING）
3. **自有物理 Tick**: 链条拥有独立的 Verlet 绳索物理模拟，每帧都需要运算
4. **LINKED 可无限持续**: 连接状态可以无限持续，直到玩家手动取消、超距断裂、怪物挣脱或死亡
5. **不阻塞移动**: 发射和取消链条不会阻塞玩家的移动（可以边走边发射）

源码中的注释明确标注了这一设计:

```gdscript
# player.gd - _unhandled_input
# === HANDOFF 推荐方案：Chain 绕过 ActionFSM，作为 overlay ===
```

---

## 4. 发射流程 (Fire Path)

链条发射完全绕过 ActionFSM，采用**延迟提交**机制避免同帧竞态:

```
player._unhandled_input(event)                  # 鼠标左键 / F键
  ├── 检查 weapon_controller.current_weapon == CHAIN
  ├── 检查奇美拉互动优先级（LINKED + is_chimera → on_player_interact）
  ├── _is_chain_fire_blocked() 检查              # 死亡/受伤/本帧受击拒绝
  ├── chain_sys.pick_fire_slot() → slot index    # 获取可用槽位
  └── _pending_chain_fire_side = "R"/"L"         # 记录，延迟到 physics tick 末尾

player._physics_process(dt)
  ├── ... (Movement → move_and_slide → Loco → Action → Health → Animator → Chain)
  └── _commit_pending_chain_fire()               # 在所有系统更新完毕后提交
        ├── 再次验证: _is_chain_fire_blocked()
        ├── 再次验证: pick_fire_slot() == expected_slot
        └── chain_sys.fire(side)                 # 实际发射
              ├── _fire_chain_at_slot(slot)       # 初始化链条物理状态
              └── _play_chain_fire_anim(slot)     # Animator.play_chain_fire()
```

### 4.1 `_fire_chain_at_slot()` 内部流程

```gdscript
func _fire_chain_at_slot(idx: int) -> void:
    var start: Vector2 = _get_hand_position(c.use_right_hand)  # 锚点获取
    var target: Vector2 = player.get_global_mouse_position()    # 鼠标世界坐标
    var dir: Vector2 = (target - start).normalized()

    _init_rope_buffers(c)          # 初始化绳索点缓冲区
    _prealloc_line_points(c)       # 预分配 Line2D 点
    _rebuild_weight_cache_if_needed(c)  # 重建波动权重缓存
    _detach_link_if_needed(idx)    # 清理旧链接

    c.state = ChainState.FLYING
    c.end_vel = dir * player.chain_speed   # 1500.0 像素/秒
    c.fly_t = 0.0
    c.wave_amp = player.rope_wave_amp      # 77.0

    EventBus.emit_chain_fired(idx)         # 通知其他系统
    _switch_to_available_slot(idx)         # 切换到空闲槽位
```

### 4.2 锚点获取优先级

手部锚点位置的获取采用三级降级策略:

```gdscript
func _get_hand_position(use_right_hand: bool) -> Vector2:
    # 1) 优先: Animator Spine 骨骼桥接
    if animator.has_method("get_chain_anchor_position"):
        return animator.get_chain_anchor_position(use_right_hand)
    # 2) Fallback: Marker2D
    var hand: Node2D = hand_r if use_right_hand else hand_l
    if hand != null:
        return hand.global_position
    # 3) 最后兜底: player 坐标
    return player.global_position
```

### 4.3 发射阻止条件

```gdscript
func _is_chain_fire_blocked() -> bool:
    if _block_chain_fire_this_frame: return true   # 本帧受击
    if health.hp <= 0: return true                  # 已死亡
    if action_fsm.state == DIE: return true         # DIE 状态
    if action_fsm.state == HURT: return true        # HURT 状态
    return false
```

另外，`fire()` 方法内部还有额外的 Die 状态硬闸检查，双重保险。

---

## 5. 取消流程 (Cancel Path)

```
player._unhandled_input(event)              # X 键
  ├── 检查 weapon == CHAIN
  ├── 检测哪些链条活跃 (right_active / left_active)
  ├── animator.play_chain_cancel(right, left)   # 先播放取消动画
  └── Tween 延迟 0.25 秒
        └── chain_sys.force_dissolve_all_chains()  # 溶解所有非 IDLE 链条
```

### 溶解实现

```gdscript
func _force_dissolve_all_chains() -> void:
    for i in range(chains.size()):
        var c = chains[i]
        if c.state == ChainState.IDLE or c.state == ChainState.DISSOLVING:
            continue
        c.wave_amp = 0.0
        _begin_burn_dissolve(i, player.cancel_dissolve_time, true)  # 0.3 秒
```

`_begin_burn_dissolve()` 内部通过 Tween 驱动 Shader 的 `burn` 参数从 0.0 到 1.0:

```gdscript
c.line.material = c.burn_mat
c.burn_mat.set_shader_parameter("burn", 0.0)
c.state = ChainState.DISSOLVING

c.burn_tw = create_tween()
c.burn_tw.tween_property(c.burn_mat, "shader_parameter/burn", 1.0, t)
c.burn_tw.tween_callback(func(): _finish_chain(i))
```

Shader 路径: `res://shaders/chain_sand_dissolve.gdshader`

---

## 6. Verlet 绳索物理

链条的视觉表现基于 Verlet 积分的绳索物理模拟，每帧在 `_sim_rope()` 中执行。

### 6.1 模拟流程

```
_sim_rope(c, start_world, end_world, dt)
  ├── 1. 锚定端点: pts[0] = start, pts[last] = end
  ├── 2. 计算端点运动增量 (start_delta, end_delta)
  ├── 3. Verlet 积分: 每个内部节点
  │     pts[k] = cur + (cur - prev) * damping + gravity
  ├── 4. 运动注入: 端点运动传导到内部节点
  │     pts[k] += end_delta * (end_motion_inject * w_end[k])
  │     pts[k] += start_delta * (hand_motion_inject * w_start[k])
  ├── 5. 自然波动叠加: sin 波沿绳索传播
  │     pts[k] += perp * sin(phase) * wave_amp * w_end[k]
  └── 6. 刚度约束: 迭代 rope_iterations 次调整相邻节点距离
```

### 6.2 权重缓存

运动注入和波动叠加使用预计算的权重数组，避免每帧重复计算:

```gdscript
func _rebuild_weight_cache_if_needed(c: ChainSlot) -> void:
    var inv: float = 1.0 / float(n - 1)
    for k in range(n):
        var t: float = float(k) * inv
        c.w_end[k] = pow(t, rope_wave_hook_power)    # 靠近钩端权重高
        c.w_start[k] = pow(1.0 - t, 1.6)             # 靠近手端权重高
```

### 6.3 波动衰减

波动幅度随时间指数衰减:

```gdscript
c.wave_amp *= exp(-rope_wave_decay * dt)
c.wave_phase += (rope_wave_freq * TAU) * dt
```

### 6.4 Line2D 渲染

支持纹理锚定方向切换（`texture_anchor_at_hook`），默认纹理起点在钩端:

```gdscript
if player.texture_anchor_at_hook:
    for i in range(n):
        c.line.set_point_position(i, c.line.to_local(c.pts[(n-1) - i]))
else:
    for i in range(n):
        c.line.set_point_position(i, c.line.to_local(c.pts[i]))
```

---

## 7. 碰撞检测 (ChainHitResolver)

FLYING 状态每帧执行双射线检测:

### 7.1 双射线策略

```gdscript
class ChainHitResolver:
    func resolve_chain_hits(c, prev_pos, end_pos) -> Dictionary:
        # 射线 1: block (墙壁 + 实体), mask = chain_hit_mask
        ray_q_block.collision_mask = player.chain_hit_mask        # 默认 9
        ray_q_block.collide_with_areas = true
        ray_q_block.collide_with_bodies = true

        # 射线 2: interact (ChainInteract 层), mask = chain_interact_mask
        ray_q_interact.collision_mask = player.chain_interact_mask  # 默认 64
        ray_q_interact.collide_with_areas = true
        ray_q_interact.collide_with_bodies = false
```

### 7.2 优先级裁决

当两条射线同时命中时，比较距离决定优先级:

```gdscript
if hit_interact.size() > 0 and hit_block.size() > 0:
    var db: float = prev_pos.distance_to(block_pos)
    var di: float = prev_pos.distance_to(interact_pos)
    allow_interact = (di <= db + 0.001)  # interact 更近或等距时优先
```

### 7.3 Block 射线的穿透逻辑

Block 射线会跳过 `chain_interact_mask` 层的碰撞体，最多迭代 6 次以穿透叠加的交互区域:

```gdscript
for _k in range(6):
    var hb = space.intersect_ray(c.ray_q_block)
    if (col_b.collision_layer & chain_interact_mask) != 0:
        ex.append(col_b.get_rid())
        continue   # 跳过，继续检测
    hit_block = hb
    break
```

---

## 8. 附着策略 (ChainAttachPolicy)

### 8.1 Interact 命中处理

对 `ChainInteract` 层的 Area2D，调用其父节点的 `on_chain_hit()`:

```gdscript
func handle_interact_hit(slot, hit_interact) -> void:
    var area: Area2D = hit_interact.get("collider")
    system._handle_interact_area(slot, area, "ray")
```

### 8.2 Block 命中处理

对 Block 命中的处理遵循以下优先级:

1. 若碰撞体在 `enemy_hurtbox` 组且有 `get_host()` 方法，向上解析宿主
2. 若宿主是 `EntityBase` 且有 `on_chain_hit()` 方法:
   - **返回 1** → 进入 LINKED 状态
   - **返回 0** → 触发 burn 溶解
3. 若宿主有 `on_chain_attached()` 方法 → 进入 LINKED 状态
4. 以上都不满足 → 触发 burn 溶解（视为墙壁命中）

### 8.3 同目标双链保护

当两条链条同时连接到同一个目标时，第二条链条不会双重连接，而是对目标造成 1 点伤害后溶解:

```gdscript
func _attach_link(slot, target, hit_pos) -> void:
    var other_slot: int = 1 - slot
    if chains[other_slot].state == ChainState.LINKED:
        if chains[other_slot].linked_target == target:
            target.call("take_damage", 1)
            _begin_burn_dissolve(slot, 0.3)
            return
```

### 8.4 连接建立

```gdscript
c.state = ChainState.LINKED
c.linked_target = target
c.linked_offset = hit_pos - target.global_position
c.is_chimera = target.is_in_group("chimera")
```

连接建立后通过 EventBus 发射 `chain_bound` 信号，携带槽位索引、目标节点、属性类型、图标 ID、是否奇美拉、是否展示动画等信息。

---

## 9. 挣脱机制 (Struggle)

非奇美拉实体在 LINKED 状态下会逐渐挣脱:

```gdscript
# ChainSlot 属性
var struggle_timer: float = 0.0
var struggle_max: float = 5.0
var is_chimera: bool = false
```

每帧更新:

```gdscript
if not c.is_chimera:
    c.struggle_timer += dt
    var progress: float = c.struggle_timer / c.struggle_max
    EventBus.emit_chain_struggle_progress(i, progress)  # 通知 UI 显示进度
    if c.struggle_timer >= c.struggle_max:
        _on_struggle_break(i)  # 挣脱 → burn 溶解
```

奇美拉（`is_in_group("chimera")`）不受挣脱机制影响，连接可无限持续。

---

## 10. LINKED 状态的断开条件

LINKED 状态在以下任一条件满足时终止:

| 条件 | 触发方式 |
|------|----------|
| 目标节点被销毁 | `linked_target == null` 或 `!is_instance_valid()` |
| 目标不可见 | `is_visible_for_chain()` 返回 `false` |
| 超距断裂 | `distance > chain_max_length`（550 像素） |
| 非奇美拉挣脱 | `struggle_timer >= struggle_max`（5 秒） |
| 玩家手动取消 | X 键 → `force_dissolve_all_chains()` |
| 受击策略 | `cancel_volatile_on_damage()` **不会**断开 LINKED（仅断 FLYING/STUCK） |
| 死亡清空 | `hard_clear_all_chains("die_enter")` |

---

## 11. 受击策略

当玩家受到伤害时:

```gdscript
# player.gd
func _on_health_damage_applied(_amount, _source_pos) -> void:
    _block_chain_fire_this_frame = true     # 本帧禁止发射
    _pending_chain_fire_side = ""           # 清空挂起的发射请求
    action_fsm.on_damaged()
```

ChainSystem 的受击策略只取消**脆弱状态**的链条:

```gdscript
func cancel_volatile_on_damage() -> void:
    for i in range(chains.size()):
        if c.state == ChainState.FLYING or c.state == ChainState.STUCK:
            force_dissolve_chain(i)   # 取消
        # LINKED 状态保留不动
```

---

## 12. 超距断裂预警

当链条长度接近 `chain_max_length` 时，Line2D 颜色渐变为警告色:

```gdscript
func _apply_break_warning_color(c, start) -> void:
    var r: float = clamp(distance / chain_max_length, 0.0, 1.0)
    if r <= warn_start_ratio:      # 0.8 → 距离低于 80% 时白色
        c.line.modulate = Color.WHITE
        return
    var t: float = (r - warn_start_ratio) / (1.0 - warn_start_ratio)
    t = pow(t, warn_gamma)         # 2.0 → 非线性加速
    c.line.modulate = Color.WHITE.lerp(warn_color, t)  # 渐变到红色
```

---

## 13. 融合系统 (Fuse System)

### 13.1 触发条件

融合需要同时满足以下所有条件:

- 两个槽位均处于 **LINKED** 状态
- 两个目标为**不同**实体
- 两个目标均处于 `weak`（虚弱）或 `is_stunned()`（眩晕）状态
- `FusionRegistry.check_fusion()` 返回非 `REJECTED` 结果
- 玩家未被锁定 (`is_player_locked() == false`)

```gdscript
func begin_fuse_cast() -> bool:
    if c0.state != ChainState.LINKED or c1.state != ChainState.LINKED:
        return false
    if c0.linked_target == c1.linked_target:
        return false

    var a_can_fuse: bool = entity_a.weak or entity_a.is_stunned()
    var b_can_fuse: bool = entity_b.weak or entity_b.is_stunned()
    if not a_can_fuse or not b_can_fuse:
        EventBus.fusion_rejected.emit()
        return false

    var result = FusionRegistry.check_fusion(entity_a, entity_b)
    if result.type == FusionRegistry.FusionResultType.REJECTED:
        EventBus.fusion_rejected.emit()
        return false
```

### 13.2 融合施法流程

```
begin_fuse_cast()
  ├── 锁定玩家: set_player_locked(true), velocity = Vector2.ZERO
  ├── 设置融合消失: entity_a.set_fusion_vanish(true), entity_b.set_fusion_vanish(true)
  ├── 溶解双链: _begin_burn_dissolve(0/1, fusion_chain_dissolve_time=0.6)
  └── 创建 Tween 延迟 fusion_lock_time (0.4 秒)
        └── commit_fuse_cast()
              ├── FusionRegistry.execute_fusion(result, player)  → 生成新实体
              ├── 解锁玩家: set_player_locked(false)
              └── 清理引用: _fuse_entity_a = null, _fuse_entity_b = null
```

### 13.3 融合中断

融合施法期间如果玩家受到伤害，执行中断:

```gdscript
func abort_fuse_cast() -> void:
    _fuse_cast_active = false
    _fuse_cast_id += 1              # 递增 ID 使延迟回调失效

    # 恢复实体可见
    _fuse_entity_a.set_fusion_vanish(false)
    _fuse_entity_b.set_fusion_vanish(false)

    player.set_player_locked(false)
    force_dissolve_all_chains()     # 溶解所有链条
```

`_fuse_cast_id` 机制确保被中断的 Tween 回调在触发时检测到 ID 不匹配而跳过执行:

```gdscript
_fuse_tween.tween_callback(func():
    if not _fuse_cast_active or cast_id != _fuse_cast_id:
        return   # 已中断，跳过
    commit_fuse_cast()
)
```

---

## 14. 硬重置 (Hard Clear)

用于死亡或场景重置时立即清空所有链条状态:

```gdscript
func hard_clear_all_chains(reason: String = "") -> void:
    for i in range(chains.size()):
        _hard_reset_slot(i)        # 杀死 Tween、detach、重置状态
    active_slot = 1                # 恢复默认
```

`_hard_reset_slot()` 确保先 detach 再改 state，保证 LINKED 状态下会正确发出 `chain_released` 事件（驱动 UI 刷新）。

调用时机:
- `player.gd` 的 `_on_die_enter()`: `chain_sys.hard_clear_all_chains("die_enter")`
- `_physics_process` 中的 Die 状态兜底: `chain_sys.hard_clear_all_chains("die_tick_guard")`

---

## 15. 内部发射碰撞检测 (Inside Interact)

链条发射时，钩端起始位置可能已经位于某个 `ChainInteract` 区域内部。此时用 `CircleShape2D`（半径 6 像素）做形状查询:

```gdscript
func _try_interact_from_inside(slot, start) -> void:
    var circle := CircleShape2D.new()
    circle.radius = 6.0
    var qp := PhysicsShapeQueryParameters2D.new()
    qp.collision_mask = player.chain_interact_mask
    var hits = space.intersect_shape(qp, 16)
    for hit in hits:
        _handle_interact_area(slot, hit.get("collider"), "inside")
```

---

## 16. ChainSlot 数据结构

```gdscript
class ChainSlot:
    var state: int = ChainState.IDLE
    var use_right_hand: bool = true
    var line: Line2D

    # 投射物状态
    var end_pos: Vector2           # 钩端世界坐标
    var end_vel: Vector2           # 飞行速度向量
    var fly_t: float               # 飞行累计时间
    var hold_t: float              # STUCK 累计时间

    # Verlet 绳索缓冲区
    var pts: PackedVector2Array    # 当前帧节点位置
    var prev: PackedVector2Array   # 上一帧节点位置（Verlet 用）
    var prev_end: Vector2          # 上帧钩端位置
    var prev_start: Vector2        # 上帧手端位置

    # 波动参数
    var wave_amp: float            # 当前波动幅度
    var wave_phase: float          # 波动相位
    var wave_seed: float           # 随机种子 (slot 0 = 0.37, slot 1 = 0.81)

    # 射线查询（预分配，避免 GC）
    var ray_q_block: PhysicsRayQueryParameters2D
    var ray_q_interact: PhysicsRayQueryParameters2D

    # Burn 溶解
    var burn_mat: ShaderMaterial
    var burn_tw: Tween

    # 权重缓存
    var w_end: PackedFloat32Array
    var w_start: PackedFloat32Array
    var cached_n: int = -1
    var cached_hook_power: float = -999.0

    # 连接状态
    var linked_target: Node2D
    var linked_offset: Vector2
    var interacted: Dictionary     # 已交互的 RID 集合（防重复）

    # 挣脱
    var struggle_timer: float = 0.0
    var struggle_max: float = 5.0
    var is_chimera: bool = false
```

---

## 17. 参数参考表

所有参数定义在 `Player.gd` 的 `@export_group("Chain System")` 中，美术可在 Inspector 直接调整。

### 投射物与距离

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `chain_speed` | 1500.0 | 链条投射物飞行速度（像素/秒） |
| `chain_max_length` | 550.0 | 链条最大长度，超出则断裂（像素） |
| `chain_max_fly_time` | 0.20 | 最大飞行时间（秒），超时转 STUCK |

### 时间参数

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `hold_time` | 0.5 | STUCK 状态持续时间（秒） |
| `burn_time` | 0.5 | 正常溶解动画时长（秒） |
| `cancel_dissolve_time` | 0.3 | 手动取消的溶解时长（秒） |
| `fusion_chain_dissolve_time` | 0.6 | 融合施法时的链条溶解时长（秒） |
| `fusion_lock_time` | 0.4 | 融合施法锁定时间（秒） |

### 绳索物理

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `rope_segments` | 22 | 绳索分段数（实际节点数 = 段数 + 1） |
| `rope_damping` | 0.88 | Verlet 阻尼系数（0~1，越大越弹） |
| `rope_gravity` | 0.0 | 绳索重力（像素/帧，0 = 无重力） |
| `rope_stiffness` | 1.7 | 刚度约束强度 |
| `rope_iterations` | 13 | 刚度约束迭代次数（越多越硬） |

### 波动效果

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `rope_wave_amp` | 77.0 | 初始波动幅度 |
| `rope_wave_decay` | 7.5 | 波动衰减速率 |
| `rope_wave_freq` | 10.0 | 波动频率 |
| `rope_wave_along_segments` | 8.0 | 沿绳索的波纹数量 |
| `rope_wave_hook_power` | 6.2 | 钩端权重曲线的幂次（越大波动越集中在钩端） |

### 运动注入

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `end_motion_inject` | 0.5 | 钩端运动注入系数 |
| `hand_motion_inject` | 0.15 | 手端运动注入系数 |

### 断裂预警

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `warn_start_ratio` | 0.8 | 开始预警的距离比例（80% 最大长度） |
| `warn_gamma` | 2.0 | 预警颜色插值的 Gamma 曲线 |
| `warn_color` | `Color(1.0, 0.3, 0.3)` | 预警颜色（红色） |

### 渲染

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `texture_anchor_at_hook` | `true` | 纹理锚点在钩端（反转 Line2D 点序） |
| `chain_shader_path` | `res://shaders/chain_sand_dissolve.gdshader` | 溶解 Shader 路径 |

### 碰撞掩码

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `chain_hit_mask` | 9 (bit 0+3) | Block 射线碰撞掩码（墙壁 + 实体） |
| `chain_interact_mask` | 64 (bit 6) | Interact 射线碰撞掩码 |

### 融合生成位置

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `spawn_try_up_count` | 8 | 向上搜索的尝试次数 |
| `spawn_try_up_step` | 16.0 | 每次向上的步进距离（像素） |
| `spawn_try_side` | 32.0 | 水平偏移距离（像素） |

---

## 18. Tick 执行顺序

链条系统在 `_physics_process` 的第 7 步执行，位于 Animator 之后以确保读取到当帧最新的骨骼锚点位置:

```
_physics_process(dt):
  1. Movement.tick(dt)         # 水平/重力/消费 jump
  2. move_and_slide()          # 物理更新
  3. LocomotionFSM.tick(dt)    # 移动状态机
  4. ActionFSM.tick(dt)        # 动作状态机
  5. Health.tick(dt)           # 无敌帧/击退
  6. Animator.tick(dt)         # 动画裁决 + 播放
  7. ChainSystem.tick(dt)      # 链条物理 + 状态更新 ← 在此
  8. _commit_pending_chain_fire()  # 提交延迟发射请求
```

---

## 19. EventBus 信号

链条系统通过 EventBus 发射以下信号:

| 信号 | 触发时机 |
|------|----------|
| `emit_chain_fired(slot)` | 链条发射时 |
| `emit_chain_bound(slot, target, attr_type, icon_id, is_chimera, show_anim)` | 链条连接到实体时 |
| `emit_chain_released(slot, reason)` | 链条断开时（reason: `"detached"` / `"dissolve"`） |
| `emit_chain_struggle_progress(slot, progress)` | 非奇美拉挣脱进度更新 |
| `emit_slot_switched(active_slot)` | 活跃槽位切换时 |
| `fusion_rejected.emit()` | 融合请求被拒绝时 |
