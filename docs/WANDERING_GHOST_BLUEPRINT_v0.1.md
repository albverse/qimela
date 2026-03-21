# 《游荡幽灵（Wandering Ghost）工程蓝图 v0.1》

> 目标：把需求整理为 **AI 可直接执行** 的工程规范（Godot 4.5 + GDScript + Beehave）。
> 说明：本蓝图严格对齐当前项目硬规则（Monster / ghost / chain / visibility / Beehave / EventBus / Spine）。
> 状态：**第一版框架指引，后续根据实际开发补充细节。**

---

## 0. 名词归一

| 需求原词 | 工程标准名 | 备注 |
|---|---|---|
| 游荡幽灵 | `WanderingGhost`（class_name） | 场景文件：`scene/enemies/wandering_ghost/WanderingGhost.tscn` |
| flymonster | `MonsterFly` | 显隐系统参考源 |
| ghostfist | `ghost_fist` | 武器 weapon_id：`&"ghost_fist"` |
| ChimeraGhostHandL | `chimera_ghost_hand_l` | 另一种可伤害幽灵的攻击来源 |
| 幽灵组 | `"ghost"` group | 加入此组后 chain 自动穿透 |
| 检测区域 | `DetectArea`（Area2D 节点） | 玩家感知范围 |
| 攻击区域 | `AttackArea`（Area2D 节点） | 近身攻击范围 |
| 显现 | `_is_visible == true` | 光照能量充足时 |
| 隐身 | `_is_visible == false` | 光照能量耗尽时 |
| 被吞食 | `_being_hunted` flag | 被噬魂狗吞食时的状态 |

---

## 1. 与当前项目硬规则的对齐约束

1. **实体类型为 Monster**：`entity_type = EntityType.MONSTER`，继承 `MonsterBase`。
2. **ghost 组成员**：`add_to_group("ghost")`，锁链（chain）自动穿透不触发碰撞。
3. **不设置 ChainInteract 碰撞层**：完全不参与 chain 交互系统。
4. **`on_chain_hit()` 返回 0**：即使被 chain raycast 命中也直接穿过。
5. **`apply_hit()` 只接受 `ghost_fist` 和 `chimera_ghost_hand_l` 的攻击**：其他 weapon_id 返回 `false`。
6. **无 HP 系统**：`has_hp = false`，被有效攻击命中后直接播放 death 动画 → `queue_free()`。
7. **无 weak / stun 状态**：不可进入虚弱态，不可被眩晕。
8. **显隐系统复用 MonsterFly 模式**：`light_counter` → `visible_time` 转换，但行为逻辑不同。
9. **隐身时仍追击玩家**（不同于 MonsterFly），但 AttackArea 的 monitoring 关闭（隐身时不攻击）。
10. **Beehave 条件节点无副作用，动作节点才执行行为**。
11. **攻击判定由 Spine 动画事件驱动**：`atk_hit_on` / `atk_hit_off` 控制 hitbox 启闭，禁止纯定时器。
12. **新增事件必须通过 EventBus `emit_*` 封装发出**，禁止直接 `.emit()`。
13. **Spine API 调用必须 `has_method()` 探测兼容 snake_case / camelCase**。
14. **信号 + 轮询双保险**：不允许状态机只靠 Spine 信号推进。
15. **动画切换禁止 `clear_track()`**：直接使用 `set_animation()` 替换。

---

## 2. 基础信息

| 字段 | 值 |
|------|-----|
| 名称 | 游荡幽灵 |
| 代码名 | `WanderingGhost` |
| 脚本文件 | `scene/enemies/wandering_ghost/wandering_ghost.gd` |
| 场景文件 | `scene/enemies/wandering_ghost/WanderingGhost.tscn` |
| 类型 | 怪物（Monster） |
| 属性 | LIGHT |
| 体型 | SMALL |
| 物种ID | `wandering_ghost` |
| 移动方式 | 飞行（悬浮） |
| 移动速度 | 80 像素/秒 |
| HP | 无（`has_hp = false`，一击死亡） |
| 虚弱阈值 | 0（无虚弱状态） |
| 泯灭次数 | 0（不可泯灭） |
| 材质节点 | SpineSprite |

---

## 3. 场景节点树

```
WanderingGhost (CharacterBody2D)
├── SpineSprite                    # Spine 动画渲染
├── CollisionShape2D               # 身体碰撞体（EnemyBody）
├── Hurtbox (Area2D)               # 受击检测
│   └── CollisionShape2D
├── DetectArea (Area2D)            # 玩家检测范围（较大）
│   └── CollisionShape2D
├── AttackArea (Area2D)            # 近身攻击范围
│   └── CollisionShape2D
├── AttackHitbox (Area2D)          # 攻击判定（由 Spine 事件启闭）
│   └── CollisionShape2D
├── LightReceiver (Area2D)         # 光照感知
│   └── CollisionShape2D
├── PointLight2D                   # 显现时发光
└── BeehaveTree                    # 行为树根节点
```

---

## 4. 碰撞层配置

```gdscript
# === CharacterBody2D (WanderingGhost) ===
collision_layer = 4   # EnemyBody(3) / Inspector 第3层
collision_mask = 1     # World(1) / Inspector 第1层

# === Hurtbox (Area2D) ===
collision_layer = 8   # EnemyHurtbox(4) / Inspector 第4层
collision_mask = 0     # 不检测任何层

# === DetectArea (Area2D) — 玩家检测 ===
collision_layer = 0
collision_mask = 2     # PlayerBody(2) / Inspector 第2层

# === AttackArea (Area2D) — 攻击范围检测 ===
collision_layer = 0
collision_mask = 2     # PlayerBody(2) / Inspector 第2层

# === AttackHitbox (Area2D) — 攻击判定 ===
collision_layer = 32   # hazards(6) / Inspector 第6层
collision_mask = 2     # PlayerBody(2) / Inspector 第2层

# === LightReceiver (Area2D) ===
collision_layer = 16  # ObjectSense(5) / Inspector 第5层
collision_mask = 16   # ObjectSense(5) / Inspector 第5层

# ❌ 不设置 ChainInteract(7) 层 — 不可被锁链交互
```

---

## 5. 显隐系统

### 5.1 与 MonsterFly 的共同点
- `light_counter` → `visible_time` 转换（速率：`dt * 10.0`）
- `visible_time` 每帧衰减
- `_switch_to_visible()` / `_switch_to_invisible()` 控制碰撞层 / 精灵 / Hurtbox

### 5.2 与 MonsterFly 的不同点

| 行为 | MonsterFly | WanderingGhost |
|------|-----------|----------------|
| 隐身时移动 | 继续巡逻 | **继续追击玩家** |
| 隐身时攻击 | 无攻击逻辑 | **AttackArea.monitoring = false，不攻击** |
| 隐身时碰撞 | collision_layer=0 | collision_layer=0（相同） |
| chain 链接 | 隐身时断链 | **始终不可 chain** |

### 5.3 显隐切换具体操作

```gdscript
# _switch_to_visible():
#   collision_layer = _saved_body_layer  (恢复 EnemyBody)
#   sprite.visible = true
#   Hurtbox: monitorable=true, monitoring=true, shape.disabled=false
#   AttackArea: monitoring=true  ← 与 MonsterFly 不同
#   PointLight2D.enabled = true

# _switch_to_invisible():
#   collision_layer = 0
#   sprite.visible = false
#   Hurtbox: monitorable=false, monitoring=false, shape.disabled=true
#   AttackArea: monitoring=false  ← 隐身时关闭攻击检测
#   PointLight2D.enabled = false
#   注：collision_mask 不清除（防止穿模）
```

---

## 6. 受击与死亡

### 6.1 `apply_hit(hit: HitData) -> bool`

参考 `GhostWraith.apply_hit()` 模式：

```gdscript
# 伪代码框架：
func apply_hit(hit: HitData) -> bool:
    if _dying or _being_hunted:
        return false
    # 只接受 ghost_fist 和 chimera_ghost_hand_l
    if hit == null:
        return false
    if hit.weapon_id != &"ghost_fist" and hit.weapon_id != &"chimera_ghost_hand_l":
        return false
    _dying = true
    _play_anim(&"death", false)
    return true
```

### 6.2 `on_chain_hit(_player, _slot) -> int`

```gdscript
func on_chain_hit(_p: Node, _s: int) -> int:
    return 0  # 链条直接穿过
```

### 6.3 death 动画完毕 → `queue_free()`

- 信号路由：`SpineSprite.animation_completed` → 检查动画名为 `death` → `queue_free()`
- 轮询兜底：每帧 poll `_dying` 状态下的 track entry `is_complete()`

---

## 7. 被吞食（噬魂狗猎杀）

当噬魂狗到达幽灵位置执行吞食时：

1. 噬魂狗调用 `ghost.start_being_hunted()`
2. 幽灵设置 `_being_hunted = true`，停止一切行为
3. 播放 `hunted` 动画（非循环）
4. 动画播完后 `queue_free()`

```gdscript
func start_being_hunted() -> void:
    _being_hunted = true
    velocity = Vector2.ZERO
    _play_anim(&"hunted", false)
    # animation_completed 信号回调中检查 hunted → queue_free()
```

---

## 8. 行为树设计（Beehave）

### 8.1 行为树结构

```
BeehaveTree (process_thread: PHYSICS)
└── SelectorReactiveComposite                    # 最外层响应式选择
    │
    ├── SequenceComposite [死亡/吞食锁定]          # 优先级最高
    │   ├── ConditionLeaf: cond_dying_or_hunted    # _dying OR _being_hunted
    │   └── ActionLeaf: act_wait_death              # 等待动画完毕 → queue_free
    │
    ├── SequenceComposite [显现状态攻击]            # 优先级 2
    │   ├── ConditionLeaf: cond_visible_and_player_in_attack_range
    │   └── ActionLeaf: act_attack                  # 播 attack，Spine 事件驱动 hitbox
    │
    ├── SequenceComposite [追击玩家]                # 优先级 3（显/隐均可）
    │   ├── ConditionLeaf: cond_player_in_detect_range
    │   └── SequenceComposite
    │       ├── ActionLeaf: act_chase_delay          # 首次进入延迟 1 秒
    │       └── ActionLeaf: act_chase_player          # 朝玩家移动
    │
    └── ActionLeaf: act_idle                        # 兜底：悬浮待机
```

### 8.2 节点详细说明

#### `cond_dying_or_hunted`
- 类型：`ConditionLeaf`
- 检查：`actor._dying == true OR actor._being_hunted == true`
- 返回：`SUCCESS` 或 `FAILURE`

#### `cond_visible_and_player_in_attack_range`
- 类型：`ConditionLeaf`
- 检查：`actor._is_visible == true AND AttackArea 内有玩家`
- 返回：`SUCCESS` 或 `FAILURE`

#### `cond_player_in_detect_range`
- 类型：`ConditionLeaf`
- 检查：`DetectArea 内有玩家`（不检查 `_is_visible`，隐身也追）
- 返回：`SUCCESS` 或 `FAILURE`

#### `act_attack`
- 类型：`ActionLeaf`
- 行为：
  1. 面向玩家
  2. 播放 `attack` 动画（`set_animation("attack", false, 0)`）
  3. Spine 事件 `atk_hit_on` → 启用 AttackHitbox
  4. Spine 事件 `atk_hit_off` → 禁用 AttackHitbox
  5. 动画完毕 → 返回 `SUCCESS`
- 返回：`RUNNING` 中 / `SUCCESS` 攻击结束

#### `act_chase_delay`
- 类型：`ActionLeaf`
- 行为：首次检测到玩家时停留 1 秒（计时器）
- 状态管理：使用 `_chase_delay_timer` 或 Blackboard 记录是否已完成延迟
- 返回：`RUNNING`（等待中） / `SUCCESS`（延迟结束）

#### `act_chase_player`
- 类型：`ActionLeaf`
- 行为：
  1. 计算玩家方向
  2. `velocity.x = direction * move_speed`
  3. 播放 `move` 动画（循环）
  4. 调用 `move_and_slide()`
- 返回：始终 `RUNNING`（由上层 condition 失败来退出）

#### `act_idle`
- 类型：`ActionLeaf`
- 行为：`velocity = Vector2.ZERO`，播放 `idle`（循环）
- 返回：`RUNNING`

---

## 9. Spine 动画清单

| 动画名 | 循环 | 轨道 | 说明 |
|--------|------|------|------|
| `idle` | 是 | 0 | 悬浮待机 |
| `move` | 是 | 0 | 追击移动 |
| `attack` | 否 | 0 | 攻击玩家；内含 `atk_hit_on` / `atk_hit_off` 事件 |
| `death` | 否 | 0 | 被 ghost_fist / ghost_hand 击杀 |
| `hunted` | 否 | 0 | 被噬魂狗吞食 |

### 9.1 Spine 事件

| 事件名 | 所在动画 | 作用 |
|--------|---------|------|
| `atk_hit_on` | `attack` | 启用 AttackHitbox（开始判定伤害） |
| `atk_hit_off` | `attack` | 禁用 AttackHitbox（关闭判定） |

### 9.2 Spine 动画播放规范

```gdscript
# 所有动画播放通过适配层或 has_method() 探测：
func _play_anim(anim_name: StringName, loop: bool) -> void:
    if _spine == null:
        return
    if _current_anim == anim_name:
        return
    _current_anim = anim_name
    var anim_state: Object = null
    if _spine.has_method("get_animation_state"):
        anim_state = _spine.get_animation_state()
    elif _spine.has_method("getAnimationState"):
        anim_state = _spine.getAnimationState()
    if anim_state == null:
        return
    # 直接 set_animation 替换，禁止先 clear_track
    if anim_state.has_method("set_animation"):
        anim_state.set_animation(String(anim_name), loop, 0)
    elif anim_state.has_method("setAnimation"):
        anim_state.setAnimation(String(anim_name), loop, 0)
```

### 9.3 动画完成信号处理

```gdscript
# 使用 animation_completed（不是 animation_ended）
func _on_anim_completed_raw(a1 = null, a2 = null, a3 = null) -> void:
    var anim_name := _extract_completed_anim_name(a1, a2, a3)
    if _dying and anim_name == &"death":
        queue_free()
    elif _being_hunted and anim_name == &"hunted":
        queue_free()
```

---

## 10. 关键参数（@export 导出）

```gdscript
@export var move_speed: float = 80.0          # 追击移动速度(像素/秒)
@export var chase_delay: float = 1.0          # 检测到玩家后的延迟(秒)
@export var visible_time_max: float = 6.0     # 最大可见时间(秒)
@export var opacity_full_threshold: float = 3.0  # 完全不透明阈值(秒)
@export var fade_curve: Curve = null           # 淡入淡出曲线
```

---

## 11. 已确认决策

1. 幽灵属性为 LIGHT，但属性实际无意义（不可 chain / fuse）。
2. `has_hp = false`，被 ghost_fist 或 chimera_ghost_hand_l 命中一次即死。
3. 无 weak / stun 系统。
4. 加入 `"ghost"` 组，chain 系统自动识别并穿透。
5. `on_chain_hit()` 返回 0，chain 不产生任何效果。
6. 隐身时继续追击玩家，但 AttackArea.monitoring 关闭（不攻击）。
7. 隐身时 Hurtbox 关闭（不可被命中），但 collision_mask 保持（不穿模）。
8. DetectArea 检测不区分显隐状态：只要玩家在范围就追。
9. 追击在玩家离开 DetectArea 后停止，回到 idle。
10. 被噬魂狗吞食时通过 `start_being_hunted()` 接口触发。
11. 显隐系统中 `collision_mask` 不在隐身时清除（与 MonsterFly 一致，防止穿入地形）。
12. Spine 事件驱动攻击判定，使用 `atk_hit_on` / `atk_hit_off` 标准事件名。
13. 动画完成判定使用 `animation_completed` 信号（非 `animation_ended`），配合轮询双保险。
14. 追击延迟 1 秒仅在玩家首次进入 DetectArea 时触发；如果玩家离开后再进入，重新触发延迟。

---

## 12. 参考文件索引

| 参考内容 | 文件 |
|---------|------|
| 显隐系统 | `scene/monster_fly.gd` |
| ghost apply_hit 模式 | `scene/enemies/boss_ghost_witch/GhostWraith.gd` |
| 基类 | `scene/monster_base.gd`、`scene/entity_base.gd` |
| Spine API 规范 | `docs/SPINE_GODOT_LATEST_INTEGRATED_STANDARD.md` |
| Beehave API | `docs/BEEHAVE_REFERENCE.md` |
| Beehave 设计指南 | `docs/E_BEEHAVE_ENEMY_DESIGN_GUIDE.md` |
| 碰撞层 | `docs/A_PHYSICS_LAYER_TABLE.md` |
| 硬约束 | `docs/CONSTRAINTS.md` |
