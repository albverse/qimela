# 《游荡幽灵（Wandering Ghost）工程蓝图 v0.4》

> 目标：把需求整理为 **AI 可直接执行** 的工程规范（Godot 4.5 + GDScript + Beehave）。
> 说明：本蓝图严格对齐当前项目硬规则（Monster / ghost / chain / visibility / Beehave / EventBus / Spine）。
> 状态：**规则已收口，可直接落地。**

---

## v0.4 变更日志（对比 v0.3）

| 序号 | 变更 | 说明 |
|------|------|------|
| FIX-V4-01 | 补 `light_receiver_path` 显式绑定 | `_ready()` 或场景中必须写 `light_receiver_path = NodePath("LightReceiver")` |
| FIX-V4-02 | 追击延迟改为"首次发现才触发" | 增加 `_has_started_chase_once` 标志，避免行为树分支切回时重复吃 1 秒延迟 |

---

## 0. 名词归一

| 需求原词 | 工程标准名 | 备注 |
|---|---|---|
| 游荡幽灵 | `WanderingGhost`（class_name） | 场景文件：`scene/enemies/wandering_ghost/WanderingGhost.tscn` |
| flymonster | `MonsterFly` | 显隐系统参考源 |
| ghostfist | `ghost_fist` | 武器 weapon_id：`&"ghost_fist"` |
| ChimeraGhostHandL | `chimera_ghost_hand_l` | 另一种可伤害幽灵的攻击来源 |
| 幽灵组 | `"ghost"` group | chain 自动穿透语义 |
| 可猎组 | `"huntable_ghost"` group | 允许被噬魂犬捕食的专用组 |
| 检测区域 | `DetectArea`（Area2D 节点） | 玩家感知范围 |
| 攻击区域 | `AttackArea`（Area2D 节点） | 近身攻击范围 |
| 显现 | `_is_visible == true` | 光照能量充足时 |
| 隐身 | `_is_visible == false` | 光照能量耗尽时 |
| 被吞食 | `_being_hunted` flag | 被噬魂犬吞食时的状态 |

---

## 1. 与当前项目硬规则的对齐约束

1. **实体类型为 Monster**：`entity_type = EntityType.MONSTER`，继承 `MonsterBase`。
2. **ghost 组成员**：`add_to_group("ghost")`，锁链（chain）自动穿透不触发碰撞。
3. **huntable_ghost 组成员**：`add_to_group("huntable_ghost")`，允许被噬魂犬捕食。
4. **不设置 ChainInteract 碰撞层**：完全不参与 chain 交互系统。
5. **`on_chain_hit()` 返回 0**：即使被 chain raycast 命中也直接穿过。
6. **`apply_hit()` 只接受 `ghost_fist` 和 `chimera_ghost_hand_l` 的攻击**：其他 weapon_id 返回 `false`。
7. **无 HP 系统**：`has_hp = false`，被有效攻击命中后直接播放 death 动画 → `queue_free()`。
8. **无 weak / stun 状态**：不可进入虚弱态，不可被眩晕。
9. **显隐系统复用 MonsterFly 模式**：`light_counter` → `visible_time` 转换，但行为逻辑不同。
10. **隐身时仍追击玩家**（不同于 MonsterFly），但 AttackArea.monitoring 关闭（隐身时不攻击）。
11. **只以玩家为追击目标**：不参与通用 `enemy_attack_target` 共享索敌。
12. **Beehave 条件节点无副作用，动作节点才执行行为**。
13. **攻击判定由 Spine 动画事件驱动**：`atk_hit_on` / `atk_hit_off` 控制 hitbox 启闭，禁止纯定时器。
14. **新增事件必须通过 EventBus `emit_*` 封装发出**，禁止直接 `.emit()`。
15. **Spine API 调用必须 `has_method()` 探测兼容 snake_case / camelCase**。（§SPINE §2.2）
16. **信号 + 轮询双保险**：不允许状态机只靠 Spine 信号推进。（§SPINE §2.3）
17. **动画切换禁止 `clear_track()`**：直接使用 `set_animation()` 替换。（§SPINE §2.4）

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

## 5. LightReceiver 绑定（FIX-V4-01）

```gdscript
# _ready() 中必须显式设置（与噬魂犬一致）
light_receiver_path = NodePath("LightReceiver")
```

> MonsterBase 默认 `light_receiver_path = ^"Hurtbox"`。游荡幽灵的 LightReceiver 是独立节点，必须覆盖。

---

## 6. 显隐系统

### 6.1 与 MonsterFly 的共同点
- `light_counter` → `visible_time` 转换（速率：`dt * 10.0`）
- `visible_time` 每帧衰减
- `_switch_to_visible()` / `_switch_to_invisible()` 控制碰撞层 / 精灵 / Hurtbox

### 6.2 与 MonsterFly 的不同点

| 行为 | MonsterFly | WanderingGhost |
|------|-----------|----------------|
| 隐身时移动 | 继续巡逻 | **继续追击玩家** |
| 隐身时攻击 | 无攻击逻辑 | **AttackArea.monitoring = false，不攻击** |
| 隐身时碰撞 | collision_layer=0 | collision_layer=0（相同） |
| chain 链接 | 隐身时断链 | **始终不可 chain** |

### 6.3 显隐切换具体操作

```gdscript
# _switch_to_visible():
#   collision_layer = _saved_body_layer  (恢复 EnemyBody)
#   sprite.visible = true
#   Hurtbox: monitorable=true, monitoring=true, shape.disabled=false
#   AttackArea: monitoring=true
#   PointLight2D.enabled = true

# _switch_to_invisible():
#   collision_layer = 0
#   sprite.visible = false
#   Hurtbox: monitorable=false, monitoring=false, shape.disabled=true
#   AttackArea: monitoring=false  ← 隐身时关闭攻击检测
#   PointLight2D.enabled = false
#   ★ 立即关闭 AttackHitbox（若正在攻击中）
#   注：collision_mask 不清除（防止穿模）
```

### 6.4 攻击过程中切入隐身的处理

当 `_is_visible` 变为 `false` 时，如果正在执行 attack 动画：

1. **立即关闭 `AttackHitbox`**（`monitoring = false`，shape disabled）
2. **当前 `attack` 动画允许播完**（不强制中断动画）
3. **attack 后半段不再产生伤害**
4. **动画结束后正常回到 chase / idle 逻辑**

---

## 7. 受击与死亡

### 7.1 `apply_hit(hit: HitData) -> bool`

```gdscript
func apply_hit(hit: HitData) -> bool:
    if _dying or _being_hunted:
        return false
    if hit == null:
        return false
    if hit.weapon_id != &"ghost_fist" and hit.weapon_id != &"chimera_ghost_hand_l":
        return false
    _dying = true
    _play_anim(&"death", false)
    return true
```

### 7.2 `on_chain_hit(_player, _slot) -> int`

```gdscript
func on_chain_hit(_p: Node, _s: int) -> int:
    return 0  # 链条直接穿过
```

### 7.3 death 动画完毕 → `queue_free()`

- 信号路由：`SpineSprite.animation_completed` → 检查动画名为 `death` → `queue_free()`
- 轮询兜底：每帧 poll `_dying` 状态下的 track entry `is_complete()`
- **使用 `animation_completed` 而非 `animation_ended`**（§SPINE §2.5）

---

## 8. 被吞食（噬魂狗猎杀）

当噬魂狗到达幽灵位置执行吞食时：

1. 噬魂狗调用 `ghost.start_being_hunted()`
2. 幽灵**立即进入完全锁死状态**

```gdscript
func start_being_hunted() -> void:
    _being_hunted = true
    velocity = Vector2.ZERO

    # 立即关闭所有碰撞/检测/行为
    $AttackArea.monitoring = false
    $AttackHitbox.monitoring = false
    $AttackHitbox.monitorable = false
    $DetectArea.monitoring = false
    $Hurtbox.monitoring = false
    $Hurtbox.monitorable = false

    _play_anim(&"hunted", false)
    # animation_completed 信号回调中检查 hunted → queue_free()
```

**被吞食期间硬规则**：
- 不得再追击玩家
- 不得再受玩家干扰（Hurtbox 已关闭）
- 不得再自行切换状态
- 行为树被 `cond_dying_or_hunted` 最高优先级锁定

---

## 9. 行为树设计（Beehave）

### 9.1 行为树结构

```
BeehaveTree (process_thread: PHYSICS)
└── SelectorReactiveComposite                    # 最外层响应式选择
    │
    ├── SequenceComposite [死亡/吞食锁定]          # P0 最高优先级
    │   ├── ConditionLeaf: cond_dying_or_hunted    # _dying OR _being_hunted
    │   └── ActionLeaf: act_wait_death              # 等待动画完毕 → queue_free
    │
    ├── SequenceComposite [显现状态攻击]            # P1
    │   ├── ConditionLeaf: cond_can_attack          # _is_visible AND player_in_attack_range AND _attack_cd_t <= 0
    │   └── ActionLeaf: act_attack                  # 播 attack，Spine 事件驱动 hitbox
    │
    ├── SequenceComposite [追击玩家]                # P2（显/隐均可）
    │   ├── ConditionLeaf: cond_player_in_detect_range
    │   └── ActionLeaf: act_chase_player            # 内含首次延迟1s逻辑
    │
    └── ActionLeaf: act_idle                        # P3 兜底
```

### 9.2 节点详细说明

#### `cond_dying_or_hunted`
- 类型：`ConditionLeaf`
- 检查：`actor._dying == true OR actor._being_hunted == true`
- 返回：`SUCCESS` 或 `FAILURE`

#### `cond_can_attack`
- 类型：`ConditionLeaf`
- 检查：`actor._is_visible == true AND AttackArea 内有玩家 AND actor._attack_cd_t <= 0.0`
- 返回：`SUCCESS` 或 `FAILURE`

#### `cond_player_in_detect_range`
- 类型：`ConditionLeaf`
- 检查：`DetectArea 内有玩家`（不检查 `_is_visible`，隐身也追）
- 返回：`SUCCESS` 或 `FAILURE`

#### `act_attack`
- 类型：`ActionLeaf`
- 行为：
  1. 面向玩家
  2. 播放 `attack` 动画（`set_animation("attack", false, 0)`）— 禁止先 clear_track
  3. Spine 事件 `atk_hit_on` → 启用 AttackHitbox（**仅在 `_is_visible == true` 时生效**）
  4. Spine 事件 `atk_hit_off` → 禁用 AttackHitbox
  5. 动画完毕 → **`_attack_cd_t = attack_cooldown`** → 返回 `SUCCESS`
- 返回：`RUNNING` 中 / `SUCCESS` 攻击结束

#### `act_chase_player`（FIX-V4-02：首次发现才延迟）
- 类型：`ActionLeaf`
- 内部状态：`_chase_phase: enum { DELAY, CHASING }`
- 外部标志：`actor._has_started_chase_once: bool`
- `before_run()`：
  - 若 `actor._has_started_chase_once == false`：`_chase_phase = DELAY`，`_delay_timer = 0.0`
  - 若 `actor._has_started_chase_once == true`：`_chase_phase = CHASING`（跳过延迟）
- 行为：
  - **DELAY 阶段**：播放 `idle`，累加 `_delay_timer`，达到 `chase_delay` 后 → `actor._has_started_chase_once = true` → `_chase_phase = CHASING`
  - **CHASING 阶段**：计算玩家方向，`velocity.x = direction * move_speed`，播放 `move`（循环），`move_and_slide()`
- 返回：始终 `RUNNING`
- `interrupt()`：`velocity = Vector2.ZERO`（不重置 `_has_started_chase_once`）

**`_has_started_chase_once` 重置时机**：当玩家离开 DetectArea 后，行为树回落到 idle，此时在 `act_idle` 中重置 `actor._has_started_chase_once = false`。这样玩家离开再进入时，重新触发 1 秒延迟。

#### `act_idle`
- 类型：`ActionLeaf`
- 行为：`velocity = Vector2.ZERO`，播放 `idle`（循环），`actor._has_started_chase_once = false`
- 返回：`RUNNING`

---

## 10. Spine 动画清单

| 动画名 | 循环 | 轨道 | 说明 |
|--------|------|------|------|
| `idle` | 是 | 0 | 悬浮待机 |
| `move` | 是 | 0 | 追击移动 |
| `attack` | 否 | 0 | 攻击玩家；内含 `atk_hit_on` / `atk_hit_off` 事件 |
| `death` | 否 | 0 | 被 ghost_fist / ghost_hand 击杀 |
| `hunted` | 否 | 0 | 被噬魂狗吞食 |

### 10.1 Spine 事件

| 事件名 | 所在动画 | 作用 |
|--------|---------|------|
| `atk_hit_on` | `attack` | 启用 AttackHitbox（仅在 `_is_visible` 时生效） |
| `atk_hit_off` | `attack` | 禁用 AttackHitbox |

### 10.2 Spine 动画播放规范

```gdscript
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
    # 直接 set_animation 替换，禁止先 clear_track（§SPINE §2.4）
    if anim_state.has_method("set_animation"):
        anim_state.set_animation(String(anim_name), loop, 0)
    elif anim_state.has_method("setAnimation"):
        anim_state.setAnimation(String(anim_name), loop, 0)
```

### 10.3 动画完成信号处理

```gdscript
# 使用 animation_completed（不是 animation_ended）（§SPINE §2.5）
func _on_anim_completed_raw(a1 = null, a2 = null, a3 = null) -> void:
    var anim_name := _extract_completed_anim_name(a1, a2, a3)
    if _dying and anim_name == &"death":
        queue_free()
    elif _being_hunted and anim_name == &"hunted":
        queue_free()
```

---

## 11. 关键参数（@export 导出）

```gdscript
@export var move_speed: float = 80.0              # 追击移动速度(像素/秒)
@export var chase_delay: float = 1.0              # 首次检测到玩家后的延迟(秒)
@export var attack_cooldown: float = 0.8          # 攻击冷却(秒)
@export var visible_time_max: float = 6.0         # 最大可见时间(秒)
@export var opacity_full_threshold: float = 3.0   # 完全不透明阈值(秒)
@export var fade_curve: Curve = null               # 淡入淡出曲线
```

### 运行时状态

```gdscript
var _attack_cd_t: float = 0.0              # 攻击冷却倒计时
var _has_started_chase_once: bool = false   # 首次追击延迟是否已执行
```

---

## 12. `_ready()` 初始化

```gdscript
func _ready() -> void:
    super._ready()
    add_to_group("ghost")             # chain 自动穿透语义
    add_to_group("huntable_ghost")    # 允许被噬魂犬捕食
    light_receiver_path = NodePath("LightReceiver")  # ★ 显式绑定
```

---

## 13. 已确认决策

1. 幽灵属性为 LIGHT，但属性实际无意义（不可 chain / fuse）。
2. `has_hp = false`，被 ghost_fist 或 chimera_ghost_hand_l 命中一次即死。
3. 无 weak / stun 系统。
4. 加入 `"ghost"` 组（chain 穿透）**和** `"huntable_ghost"` 组（可被噬魂犬捕食）。两组职责不可混用。
5. `on_chain_hit()` 返回 0。
6. 隐身时继续追击玩家，但 AttackArea.monitoring 关闭。
7. 隐身时 Hurtbox 关闭，collision_mask 保持。
8. DetectArea 不区分显隐状态。
9. 追击在玩家离开 DetectArea 后停止，回到 idle。
10. 被吞食通过 `start_being_hunted()` 触发，进入**完全锁死**。
11. 攻击有 0.8s CD。
12. 攻击中隐身：立即关 AttackHitbox，动画播完，后半段无伤害。
13. 只追击玩家，不参与通用 `enemy_attack_target`。
14. 追击延迟 1 秒仅在**首次发现玩家时**触发；玩家离开后再进入重新触发。
15. `light_receiver_path` 显式绑定为 `NodePath("LightReceiver")`。

---

## 14. 参考文件索引

| 参考内容 | 文件 |
|---------|------|
| 显隐系统 | `scene/monster_fly.gd` |
| ghost apply_hit 模式 | `scene/enemies/boss_ghost_witch/GhostWraith.gd` |
| 基类 | `scene/monster_base.gd`、`scene/entity_base.gd` |
| Spine API 规范 | `docs/SPINE_GODOT_LATEST_INTEGRATED_STANDARD.md` |
| Beehave API（含 D-01~D-16） | `docs/BEEHAVE_REFERENCE.md` |
| Beehave 设计指南 | `docs/E_BEEHAVE_ENEMY_DESIGN_GUIDE.md` |
| 碰撞层 | `docs/A_PHYSICS_LAYER_TABLE.md` |
| 硬约束 | `docs/CONSTRAINTS.md` |
