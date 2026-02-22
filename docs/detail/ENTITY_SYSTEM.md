# Entity System (实体系统)

本文档详细描述游戏中 Entity、Monster、Chimera 三层继承体系的设计与实现。
所有实体均继承自 `CharacterBody2D`，通过统一的基类 `EntityBase` 管理属性、HP、锁链交互、泯灭融合等核心机制。

---

## 目录

1. [继承结构总览](#继承结构总览)
2. [EntityBase -- 实体基类](#entitybase----实体基类)
   - [枚举定义](#枚举定义)
   - [核心属性](#核心属性)
   - [HP 系统](#hp-系统)
   - [泯灭融合系统](#泯灭融合系统)
   - [锁链交互](#锁链交互)
   - [融合消失](#融合消失-set_fusion_vanish)
   - [视觉效果](#视觉效果)
3. [MonsterBase -- 怪物基类](#monsterbase----怪物基类)
   - [眩晕系统](#眩晕系统)
   - [光照系统](#光照系统)
   - [锁链交互重写](#锁链交互重写)
   - [虚弱状态流程](#虚弱状态流程)
4. [具体怪物类型](#具体怪物类型)
   - [MonsterWalk (暗属性地面行走怪)](#monsterwalk)
   - [MonsterWalkB (紫色暗属性走怪变种)](#monsterwalkb)
   - [MonsterFly (光属性飞行怪 -- 显隐机制)](#monsterfly)
   - [MonsterFlyB (金色光属性飞怪变种)](#monsterflyb)
   - [MonsterNeutral (无属性中立怪)](#monsterneutral)
   - [MonsterHostile (敌对怪物 -- 融合失败产物)](#monsterhostile)
   - [MonsterHand (怪手)](#monsterhand)
5. [ChimeraBase -- 奇美拉基类](#chimerabase----奇美拉基类)
   - [来源类型](#来源类型-chimeraorigintype)
   - [跟随与漫游行为](#跟随与漫游行为)
   - [分解机制](#分解机制-chimera_chimera-限定)
   - [玩家互动接口](#玩家互动接口)
6. [具体奇美拉类型](#具体奇美拉类型)
   - [ChimeraA (标准奇美拉)](#chimeraa)
   - [ChimeraStoneSnake (石蛇奇美拉)](#chimerastonesnake)
   - [ChimeraTemplate (模板)](#chimeratemplate)
7. [怪物属性速查表](#怪物属性速查表)
8. [关键设计要点](#关键设计要点)

---

## 继承结构总览

```
CharacterBody2D
  └── EntityBase (entity_base.gd)
        ├── MonsterBase (monster_base.gd)
        │     ├── MonsterWalk (monster_walk.gd)
        │     ├── MonsterWalkB (monster_walk_b.gd)
        │     ├── MonsterFly (monster_fly.gd)
        │     ├── MonsterFlyB (monster_fly_b.gd)
        │     ├── MonsterNeutral (monster_neutral.gd)
        │     ├── MonsterHostile (monster_hostile.gd)
        │     └── MonsterHand (monster_hand.gd)
        └── ChimeraBase (chimera_base.gd)
              ├── ChimeraA (chimera_a.gd)
              ├── ChimeraStoneSnake (chimera_stone_snake.gd)
              └── ChimeraTemplate (chimera_template.gd)
```

---

## EntityBase -- 实体基类

**文件:** `scene/entity_base.gd`
**继承:** `CharacterBody2D`
**class_name:** `EntityBase`

所有怪物和奇美拉的公共基类。统一管理属性系统、HP 系统、泯灭融合系统、锁链交互和视觉效果。

### 枚举定义

| 枚举 | 值 | 说明 |
|------|-----|------|
| `AttributeType.NORMAL` | 0 | 无属性，可与任何属性融合，不触发光暗冲突 |
| `AttributeType.LIGHT` | 1 | 光属性 |
| `AttributeType.DARK` | 2 | 暗属性 |
| `SizeTier.SMALL` | 0 | 小型，影响融合结果和治愈精灵数量 |
| `SizeTier.MEDIUM` | 1 | 中型 |
| `SizeTier.LARGE` | 2 | 大型 |
| `EntityType.MONSTER` | 0 | 野生怪物 |
| `EntityType.CHIMERA` | 1 | 融合产物（奇美拉）|
| `FailType.RANDOM` | 0 | 融合失败时随机选择结果 |
| `FailType.HOSTILE` | 1 | 融合失败时生成敌对怪物 |
| `FailType.VANISH` | 2 | 融合失败时双方泯灭，生成治愈精灵 |
| `FailType.EXPLODE` | 3 | 融合失败时爆炸+烂泥（仅奇美拉+奇美拉可能触发）|

### 核心属性

通过 Inspector 配置的导出变量：

```gdscript
@export var attribute_type: AttributeType = AttributeType.NORMAL  # 实体属性
@export var size_tier: SizeTier = SizeTier.SMALL                  # 实体型号
@export var species_id: StringName = &""                          # 物种ID（融合规则匹配用）
@export var entity_type: EntityType = EntityType.MONSTER           # 实体类型
@export var fusion_fail_type: FailType = FailType.RANDOM          # 融合失败结果类型
@export var fusion_damage_percent: float = 0.15                   # 光暗冲突HP损失百分比
```

**`species_id` 的作用:** 同 `species_id` 的两个实体无法互相融合，以此区分不同物种。

**`fusion_damage_percent` 的作用:** 当光属性与暗属性实体融合且型号不同时，大型怪物会损失此百分比的 HP。

### HP 系统

#### 导出变量

```gdscript
@export var has_hp: bool = true     # 是否拥有HP系统（false = 无法被攻击）
@export var max_hp: int = 3         # 最大生命值
@export var weak_hp: int = 1        # HP <= 此值时进入虚弱状态
```

#### 运行时变量

```gdscript
var hp: int = 3                     # 当前生命值
var weak: bool = false              # 是否处于虚弱状态
var hp_locked: bool = false         # 虚弱时HP锁定，普通攻击无法减少HP
```

#### 核心方法

| 方法 | 说明 |
|------|------|
| `take_damage(amount: int)` | 受到普通伤害。若 `hp_locked` 为 `true` 则只播放闪白不扣血。否则减少 HP 并更新虚弱状态。HP 归零且未锁定时触发 `_on_death()` |
| `heal(amount: int)` | 恢复指定量的 HP，上限为 `max_hp`。若回复后 HP 超过 `weak_hp` 则退出虚弱状态 |
| `heal_percent(percent: float)` | 按百分比恢复 HP，内部调用 `heal(int(ceil(max_hp * percent)))` |
| `_update_weak_state()` | 检查并更新虚弱状态。首次进入虚弱时设置 `hp_locked = true` 并重置泯灭计数 |
| `_on_death()` | 死亡处理，基类实现为 `queue_free()` |

#### HP 流程图

```
正常状态 (hp > weak_hp)
    │
    │ take_damage() → hp 减少
    │
    ▼ hp <= weak_hp
虚弱状态 (weak = true, hp_locked = true)
    │
    ├── 普通攻击 → 只闪白，不扣血
    ├── 泯灭融合 → vanish_fusion_count +1
    │     └── 达到阈值 → 死亡
    └── 恢复（MonsterBase: weak_stun_t 耗尽 → 全回满）
```

### 泯灭融合系统

泯灭融合是虚弱期间的核心杀死机制。普通攻击无法在虚弱状态下进一步减少 HP，只有泯灭性融合才能击杀。

#### 配置

```gdscript
@export var vanish_fusion_required: int = 1  # 需要多少次泯灭融合才会死亡
var vanish_fusion_count: int = 0             # 当前已承受的泯灭融合次数
```

每只怪物可以配置不同的 `vanish_fusion_required` 值：
- `1`：一次融合就死（默认，大多数怪物）
- `2`：需要两次融合才会死（如 `MonsterFly`）
- 更高值：更耐久的怪物

#### 核心方法

| 方法 | 返回值 | 说明 |
|------|--------|------|
| `apply_vanish_fusion()` | `bool` | 对虚弱实体施加一次泯灭融合。返回 `true` 表示达到阈值应该死亡，`false` 表示继续存活 |
| `get_vanish_progress()` | `float` | 获取泯灭进度 (0.0 ~ 1.0)，用于 UI 进度条显示 |
| `get_vanish_remaining()` | `int` | 获取剩余所需的泯灭次数 |
| `reset_vanish_count()` | `void` | 重置泯灭计数（从虚弱恢复时调用）|

#### 实现细节

```gdscript
func apply_vanish_fusion() -> bool:
    if not weak:
        return false
    vanish_fusion_count += 1
    if vanish_fusion_count >= vanish_fusion_required:
        return true   # 达到阈值，应该死亡
    return false      # 未达到阈值，继续存活
```

### 锁链交互

锁链是玩家与实体之间的核心交互机制。玩家可以通过锁链命中实体，根据实体状态决定是链接还是造成伤害。

#### 变量

```gdscript
var _linked_slot: int = -1            # 被哪条锁链链接（-1 = 未链接, 0 = 链0, 1 = 链1）
var _linked_player: Node = null       # 链接到的玩家引用
var _hurtbox_original_layer: int = -1 # 保存原始碰撞层
@onready var _hurtbox: Area2D = get_node_or_null("Hurtbox") as Area2D
```

#### 核心方法

| 方法 | 说明 |
|------|------|
| `on_chain_hit(_player, _slot) -> int` | 锁链命中时调用。基类返回 `0`（普通受击）。`MonsterBase` 和 `ChimeraBase` 各自重写 |
| `on_chain_attached(slot: int)` | 锁链连接成功。保存并禁用 Hurtbox 碰撞层（防止重复受击），播放闪白 |
| `on_chain_detached(slot: int)` | 锁链断开。恢复 Hurtbox 碰撞层，清空链接引用 |
| `is_linked() -> bool` | 返回是否被锁链链接（`_linked_slot >= 0`）|
| `get_linked_slot() -> int` | 返回当前链接的槽位编号 |
| `is_occupied_by_other_chain(requesting_slot) -> bool` | 是否已被另一条锁链占用 |

#### 返回值约定

`on_chain_hit` 的返回值决定锁链系统的后续行为：
- **`0`** = 普通受击（锁链溶解消失，不建立连接）
- **`1`** = 可链接（进入 LINKED 状态，锁链保持连接）

### 融合消失 (set_fusion_vanish)

当实体参与融合时，需要暂时隐藏（消失）。此方法统一定义在 `EntityBase` 中，`MonsterBase` 和 `ChimeraBase` 不再各自实现。

```gdscript
var _saved_collision_layer_fv: int = -1
var _saved_collision_mask_fv: int = -1
var _fusion_vanished: bool = false

func set_fusion_vanish(v: bool) -> void:
    if v:
        # 消失：保存并清零碰撞层，隐藏 sprite
        if not _fusion_vanished:
            _saved_collision_layer_fv = collision_layer
            _saved_collision_mask_fv = collision_mask
            _fusion_vanished = true
        collision_layer = 0
        collision_mask = 0
    else:
        # 恢复：还原碰撞层，显示 sprite
        if _fusion_vanished:
            collision_layer = _saved_collision_layer_fv
            collision_mask = _saved_collision_mask_fv
            _fusion_vanished = false
    if sprite != null:
        sprite.visible = not v
```

**关键点:** 消失时保存碰撞层/掩码，恢复时精确还原。避免了多次调用导致的状态丢失（仅首次消失时保存）。

### 视觉效果

#### 闪白效果

闪白效果用于表示受击、链接等反馈。实现方式是将 sprite 的 `modulate` 和 `self_modulate` 短暂设为高亮，然后通过 Tween 渐变回原始颜色。

```gdscript
@export var visual_item_path: NodePath = NodePath("")  # 视觉节点路径
@export var flash_time: float = 0.2                    # 闪白持续时间（秒）
```

#### 视觉节点查找顺序

`_find_visual()` 方法按以下优先级查找视觉节点：

1. `visual_item_path` 指定的节点
2. 名为 `Sprite2D` 的子节点
3. 名为 `Visual` 的子节点
4. 第一个 `CanvasItem` 类型的子节点

#### 颜色保存机制

原始颜色在 `_ready()` 中通过 `call_deferred("_save_original_colors")` 延迟保存，确保 sprite 已完成初始化。闪白结束后精确恢复到保存的颜色，不会出现颜色漂移。

```gdscript
func _flash_once() -> void:
    # 设置高亮
    sprite.modulate = Color(1.0, 1.0, 1.0, _original_modulate.a)
    sprite.self_modulate = Color(1.8, 1.8, 1.8, _original_self_modulate.a)
    # Tween 回到原始颜色
    _flash_tw = create_tween()
    _flash_tw.tween_property(sprite, "modulate", _original_modulate, flash_time)
    _flash_tw.parallel().tween_property(sprite, "self_modulate", _original_self_modulate, flash_time)
```

---

## MonsterBase -- 怪物基类

**文件:** `scene/monster_base.gd`
**继承:** `EntityBase`
**class_name:** `MonsterBase`

所有野生怪物的基类。在 `EntityBase` 基础上增加了眩晕系统、光照系统、以及更复杂的锁链交互和虚弱恢复逻辑。

### 初始化

```gdscript
func _ready() -> void:
    super._ready()
    entity_type = EntityType.MONSTER
    add_to_group("monster")
    # 连接 EventBus 信号
    EventBus.thunder_burst.connect(_on_thunder_burst)
    EventBus.light_started.connect(_on_light_started)
    EventBus.light_finished.connect(_on_light_finished)
    EventBus.healing_burst.connect(_on_healing_burst)
```

所有怪物自动加入 `"monster"` 组，并监听全局事件总线的光照相关信号。

### 眩晕系统

怪物拥有两套独立的眩晕机制：普通眩晕 (`stunned_t`) 和虚弱眩晕 (`weak_stun_t`)。

#### 配置参数

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `hit_stun_time` | `0.1s` | 普通受击时的短暂眩晕 |
| `weak_stun_time` | `5.0s` | 进入虚弱状态后的眩晕持续时间 |
| `weak_stun_extend_time` | `3.0s` | 锁链连接时延长的眩晕时间 |
| `stun_duration` | `2.0s` | 可配置的外部眩晕持续时间（被光花等击中时使用）|
| `healing_burst_stun_time` | `3.0s` | 被治愈精灵大爆炸击中时的眩晕时长 |

#### 运行时变量

```gdscript
var stunned_t: float = 0.0     # 当前普通眩晕剩余时间
var weak_stun_t: float = 0.0   # 虚弱状态眩晕剩余时间
```

#### 核心方法

| 方法 | 说明 |
|------|------|
| `is_stunned() -> bool` | 重写基类方法，返回 `stunned_t > 0.0` |
| `apply_stun(seconds, do_flash)` | 施加普通眩晕，取当前剩余和传入时间的较大值 |
| `apply_healing_burst_stun()` | 被治愈精灵爆炸击中时施加专属眩晕 |

#### 物理帧处理优先级

`_physics_process(dt)` 中的处理顺序：

```
1. 更新 light_counter（持续递减）
2. 重置 _thunder_processed_this_frame 标志
3. 若处于虚弱状态 (weak = true):
   └── 递减 weak_stun_t → 耗尽时调用 _restore_from_weak() → return
4. 若处于普通眩晕 (stunned_t > 0):
   └── 递减 stunned_t → 耗尽时释放锁链 → return
5. 执行 _do_move(dt)（正常移动逻辑，由子类重写）
```

**关键点:** 虚弱检查优先于眩晕检查，两者都会跳过移动逻辑。

### 光照系统

怪物可以对光照产生反应。光照计数器 (`light_counter`) 累积来自不同光源的能量。

#### 配置参数

```gdscript
@export var light_counter: float = 0.0          # 当前光照能量
@export var light_counter_max: float = 10.0      # 光照能量上限
@export var thunder_add_seconds: float = 3.0     # 雷电增加的光照时间
@export var light_receiver_path: NodePath = ^"Hurtbox"  # 光照接收区域
```

#### 响应的信号

| 信号 | 处理方法 | 行为 |
|------|----------|------|
| `EventBus.thunder_burst` | `_on_thunder_burst(add_seconds)` | 增加光照能量（每帧只处理一次）|
| `EventBus.light_started` | `_on_light_started(source_id, remaining_time, area)` | 光源开始照射，检测重叠后增加能量 |
| `EventBus.light_finished` | `_on_light_finished(source_id)` | 光源结束，清理跟踪字典 |
| `EventBus.healing_burst` | `_on_healing_burst(light_energy)` | 治愈精灵爆炸，全场增加光照能量 |

#### 光源跟踪机制

```gdscript
var _processed_light_sources: Dictionary = {}  # 已处理的光源（避免重复计算）
var _active_light_sources: Dictionary = {}     # 活跃但尚未重叠的光源（延迟检测）
```

当 `light_started` 触发时，若光源区域尚未与怪物的 `_light_receiver` 重叠，则存入 `_active_light_sources` 待后续检测。当 `_light_receiver` 的 `area_entered` 触发时，再回查并处理。

### 锁链交互重写

`MonsterBase` 对基类的锁链交互进行了重要扩展。

#### on_chain_hit 逻辑

```gdscript
func on_chain_hit(_player: Node, _slot: int) -> int:
    if weak or stunned_t > 0.0:
        _linked_player = _player
        return 1   # 虚弱或眩晕时可链接
    take_damage(1)  # 正常状态受击扣1点HP
    return 0        # 不可链接
```

**核心规则:** 怪物只有在虚弱或眩晕状态下才能被锁链链接。正常状态下锁链命中只造成 1 点伤害。

#### 多锁链支持

```gdscript
var _linked_slots: Array[int] = []  # 支持多条锁链同时链接
```

`MonsterBase` 使用数组 `_linked_slots` 追踪所有链接的锁链，而不是基类的单一 `_linked_slot`。

#### on_chain_attached 扩展

```gdscript
func on_chain_attached(slot: int) -> void:
    # 第一条链连接时禁用 Hurtbox 碰撞层
    if _linked_slots.is_empty():
        if _hurtbox != null:
            _hurtbox_original_layer = _hurtbox.collision_layer
            _hurtbox.collision_layer = 0
    if not _linked_slots.has(slot):
        _linked_slots.append(slot)
    _linked_slot = slot
    # 延长虚弱/眩晕时间
    if weak:
        weak_stun_t += weak_stun_extend_time
    elif stunned_t > 0.0:
        stunned_t += weak_stun_extend_time
    _flash_once()
```

**关键点:** 每次链接成功都会延长眩晕/虚弱时间 (`weak_stun_extend_time`)，给玩家更多操作窗口。

#### on_chain_detached 扩展

```gdscript
func on_chain_detached(slot: int) -> void:
    _linked_slots.erase(slot)
    if _linked_slots.is_empty():
        # 所有链断开：恢复 Hurtbox，清空引用
        _linked_slot = -1
        _linked_player = null
        if _hurtbox != null and _hurtbox_original_layer >= 0:
            _hurtbox.collision_layer = _hurtbox_original_layer
            _hurtbox_original_layer = -1
    else:
        _linked_slot = _linked_slots[0]  # 更新为剩余的第一条链
```

### 虚弱状态流程

虚弱状态是怪物可以被击杀的关键窗口期。

#### 进入虚弱

```
HP 降至 <= weak_hp
  └── _update_weak_state()
        ├── weak = true
        ├── hp_locked = true          ← 普通攻击不再扣血
        ├── vanish_fusion_count = 0   ← 重置泯灭计数
        └── weak_stun_t = weak_stun_time (5.0s)  ← 开始虚弱眩晕倒计时
```

#### 虚弱期间

- 怪物停止移动（`_do_move` 检查 `weak` 状态）
- 锁链命中返回 `1`（可链接）
- 每次锁链连接延长 `weak_stun_t`
- 泯灭融合可以累积 `vanish_fusion_count`，达到阈值时死亡
- 普通攻击只触发闪白，不扣血

#### 从虚弱恢复

```gdscript
func _restore_from_weak() -> void:
    hp = max_hp              # 回满HP
    weak = false             # 退出虚弱
    hp_locked = false        # 解除HP锁定
    weak_stun_t = 0.0        # 清除虚弱眩晕
    reset_vanish_count()     # 重置泯灭计数
    _release_linked_chains() # 释放所有锁链
```

当 `weak_stun_t` 自然耗尽（玩家未能在时间窗口内完成击杀），怪物完全恢复，回满 HP，释放所有锁链。

#### 锁链释放机制

```gdscript
func _release_linked_chains() -> void:
    # 1. 复制并清空链接列表
    # 2. 恢复 Hurtbox 碰撞层
    # 3. 通知 Player 的 ChainSystem 溶解锁链
```

通知方式按优先级尝试：
1. `Player.force_dissolve_chain(slot)`
2. `Player.chain_sys.force_dissolve_chain(slot)`

---

## 具体怪物类型

### MonsterWalk

**文件:** `scene/monster_walk.gd`
**class_name:** `MonsterWalk`

暗属性地面行走怪物，最基础的敌人类型。

| 属性 | 值 |
|------|-----|
| `species_id` | `walk_dark` |
| `attribute_type` | `DARK` |
| `size_tier` | `SMALL` |
| `max_hp` | 5 |
| `weak_hp` | 1 |
| `vanish_fusion_required` | 1 |
| `move_speed` | 70.0 px/s |

**行为:**
- 受重力影响，在地面上左右巡逻
- 碰到墙壁自动转向 (`is_on_wall()` 检测)
- 虚弱时完全停止移动

### MonsterWalkB

**文件:** `scene/monster_walk_b.gd`
**class_name:** `MonsterWalkB`

紫色暗属性走怪变种，用于测试暗+暗融合失败场景。

| 属性 | 值 |
|------|-----|
| `species_id` | `walk_dark_b` |
| `attribute_type` | `DARK` |
| `size_tier` | `SMALL` |
| `max_hp` | 4 |
| `weak_hp` | 1 |
| `vanish_fusion_required` | 1 |
| `move_speed` | 80.0 px/s（比普通走怪快）|

**行为:** 与 `MonsterWalk` 基本相同，但移动速度更快，HP 较低。

**设计意图:** 与 `MonsterWalk` 拥有不同的 `species_id`（`walk_dark_b` vs `walk_dark`），使两者可以融合。两个暗属性怪物融合会触发 FAIL_HOSTILE。

### MonsterFly

**文件:** `scene/monster_fly.gd`
**class_name:** `MonsterFly`

光属性飞行怪物，拥有独特的显隐机制。

| 属性 | 值 |
|------|-----|
| `species_id` | `fly_light` |
| `attribute_type` | `LIGHT` |
| `size_tier` | `SMALL` |
| `max_hp` | 3 |
| `weak_hp` | 1 |
| `vanish_fusion_required` | **2**（需要两次泯灭融合）|
| `move_speed` | 90.0 px/s |

**显隐机制 (Visibility System):**

这是 `MonsterFly` 最核心的特殊机制。飞行怪默认处于不可见状态，只有受到光照时才会显形。

#### 可见性参数

```gdscript
@export var visible_time: float = 0.0          # 当前剩余可见时间
@export var visible_time_max: float = 6.0       # 最大可见时间
@export var opacity_full_threshold: float = 3.0  # 完全不透明的阈值
@export var fade_curve: Curve = null             # 淡入淡出曲线
```

#### 状态切换

**不可见状态 (`_switch_to_invisible`):**
- `collision_layer = 0`（碰撞层清零）
- Sprite 隐藏，透明度设为 0
- Hurtbox 的 `monitorable` 和 `monitoring` 设为 `false`
- CollisionShape2D 禁用
- PointLight2D 关闭

**可见状态 (`_switch_to_visible`):**
- 恢复保存的碰撞层/掩码
- Sprite 显示，透明度设为 1
- Hurtbox 启用
- PointLight2D 打开

#### 可见时间流转

```
光照能量 (light_counter > 0)
  └── 以 dt * 10.0 速率转化为 visible_time
        └── visible_time > 0 → 可见
              └── visible_time 持续递减
                    └── visible_time <= 0 → 不可见
                          └── 强制释放所有锁链
```

#### 透明度计算

```gdscript
# visible_time >= opacity_full_threshold → 完全不透明 (alpha = 1.0)
# visible_time < opacity_full_threshold → 按比例渐变 (可使用 fade_curve)
```

#### 不可见时的特殊行为

当飞行怪变为不可见时，会强制释放所有已连接的锁链：

```gdscript
func _on_visibility_timeout() -> void:
    _switch_to_invisible()
    _force_release_all_chains()
```

**移动方式:** 飞行怪不受重力影响，以正弦波形上下浮动，同时水平左右移动。碰墙转向。

```gdscript
global_position.y = _base_y + sin(_t * TAU * float_freq) * float_amp
```

### MonsterFlyB

**文件:** `scene/monster_fly_b.gd`
**class_name:** `MonsterFlyB`

金色光属性飞怪变种，用于测试光+光融合失败场景。

| 属性 | 值 |
|------|-----|
| `species_id` | `fly_light_b` |
| `attribute_type` | `LIGHT` |
| `size_tier` | `SMALL` |
| `max_hp` | 2 |
| `weak_hp` | 1 |
| `vanish_fusion_required` | 1 |
| `move_speed` | 100.0 px/s（比普通飞怪快）|

**行为:** 与 `MonsterFly` 的移动方式相同（浮空左右飘+正弦浮动），但**没有显隐机制**。始终可见。

### MonsterNeutral

**文件:** `scene/monster_neutral.gd`
**class_name:** `MonsterNeutral`

无属性中立怪物。可与任何属性的实体融合，不会触发光暗冲突。

| 属性 | 值 |
|------|-----|
| `species_id` | `neutral_small` |
| `attribute_type` | `NORMAL` |
| `size_tier` | `SMALL` |
| `max_hp` | 3 |
| `weak_hp` | 1 |
| `vanish_fusion_required` | 1 |
| `move_speed` | 50.0 px/s（最慢）|

**行为:** 地面巡逻，碰墙转向。移动速度最慢，被动型怪物。

### MonsterHostile

**文件:** `scene/monster_hostile.gd`
**class_name:** `MonsterHostile`

敌对怪物，由融合失败产生。**没有虚弱状态**，是唯一可以通过普通攻击直接杀死的怪物类型。

| 属性 | 值 |
|------|-----|
| `species_id` | `hostile_fail` |
| `attribute_type` | `NORMAL` |
| `size_tier` | `MEDIUM` |
| `max_hp` | 5 |
| `weak_hp` | **0**（永远不会进入虚弱）|
| `vanish_fusion_required` | 1 |
| `move_speed` | 100.0 px/s（最快的地面怪）|
| `healing_drop_count` | 2 |

**特殊设计:**
- `weak_hp = 0` 意味着 HP 永远不会 `<= weak_hp && > 0`，因此永远不会进入虚弱状态
- `hp_locked` 永远为 `false`，普通攻击可以一直扣血直到死亡
- 移动速度最快 (100 px/s)，对玩家构成威胁
- 加入 `"hostile_monster"` 组
- `fusion_fail_type = FailType.HOSTILE`（再次融合失败也生成敌对怪）

**死亡掉落:**

```gdscript
func _on_death() -> void:
    _spawn_healing_sprites()  # 生成治愈精灵
    queue_free()
```

死亡时加载 `res://scene/HealingSprite.tscn`，在自身位置附近随机偏移生成 `healing_drop_count` 只治愈精灵。

### MonsterHand

**文件:** `scene/monster_hand.gd`
**class_name:** `MonsterHand`

怪手怪物，光属性飞行类型。

| 属性 | 值 |
|------|-----|
| `species_id` | `hand_light` |
| `attribute_type` | `LIGHT` |
| `size_tier` | `SMALL` |
| `max_hp` | 3 |
| `weak_hp` | 1 |
| `vanish_fusion_required` | 1 |
| `move_speed` | 100.0 px/s |

**行为:** 浮空左右移动，正弦波上下浮动，碰墙转向。与 `MonsterFlyB` 的移动方式一致。

---

## ChimeraBase -- 奇美拉基类

**文件:** `scene/chimera_base.gd`
**继承:** `EntityBase`
**class_name:** `ChimeraBase`

奇美拉是怪物融合后的产物。与怪物不同，奇美拉通常可以被玩家链接并跟随，提供各种能力。

### 初始化

```gdscript
func _ready() -> void:
    super._ready()
    entity_type = EntityType.CHIMERA
    has_hp = can_be_attacked  # HP系统由 can_be_attacked 控制
    add_to_group("chimera")
```

### 来源类型 (ChimeraOriginType)

```gdscript
enum ChimeraOriginType {
    MONSTER_MONSTER = 1,   # 两只怪物融合
    CHIMERA_MONSTER = 2,   # 奇美拉 + 怪物融合
    CHIMERA_CHIMERA = 3,   # 两只奇美拉融合（可分解！）
    PRIMORDIAL = 4         # 预置（场景中直接放置）
}
```

`origin_type` 决定奇美拉的来源，最重要的区分是 **类型 3 (CHIMERA_CHIMERA)** 可以在断链时触发分解。

### 导出属性

```gdscript
@export var origin_type: ChimeraOriginType = ChimeraOriginType.MONSTER_MONSTER
@export var can_be_attacked: bool = false       # 是否可被攻击
@export var follow_player_when_linked: bool = true  # 链接时是否跟随玩家
@export var move_speed: float = 170.0           # 移动速度
@export var is_flying: bool = false             # 飞行 vs 地面移动
@export var gravity: float = 1500.0             # 重力（地面单位使用）
@export var accel: float = 1400.0               # 加速度
@export var stop_threshold_x: float = 6.0       # 接近玩家多少像素时停止
@export var x_offset: float = 0.0               # 跟随时的水平偏移
```

### 跟随与漫游行为

#### 物理帧处理

```gdscript
func _physics_process(dt: float) -> void:
    if is_linked() and follow_player_when_linked and _player != null:
        _move_toward_player(dt)  # 链接状态：跟随玩家
    else:
        _idle_behavior(dt)       # 未链接：随机漫游
    move_and_slide()
```

#### 跟随玩家

根据 `is_flying` 区分两种跟随方式：

**飞行跟随:**
- 计算与玩家的方向向量
- 使用 `velocity.move_toward()` 平滑加速
- 距离小于 `stop_threshold_x` 时减速停止

**地面跟随:**
- 受重力影响
- 仅在水平方向追踪玩家位置（加上 `x_offset`）
- 使用 `move_toward()` 平滑加速/减速

#### 随机漫游

未链接时执行简单的随机漫游：

```gdscript
func _idle_behavior(dt: float) -> void:
    if not is_flying:
        velocity.y += gravity * dt
    _wander_t -= dt
    if _wander_t <= 0.0:
        _pick_next_wander()      # 随机选择方向和持续时间
    var desired := float(_wander_dir) * move_speed * 0.5  # 半速漫游
    velocity.x = move_toward(velocity.x, desired, accel * dt)

func _pick_next_wander() -> void:
    _wander_dir = _rng.randi_range(-1, 1)   # -1, 0, 或 1
    _wander_t = _rng.randf_range(1.0, 4.0)  # 1~4秒
```

### 锁链交互

```gdscript
func on_chain_hit(_player_ref: Node, slot: int) -> int:
    if is_occupied_by_other_chain(slot):
        return 0  # 已被其他链占用
    _linked_player = _player_ref
    _player = _player_ref as Node2D
    return 1      # 奇美拉默认可链接
```

**与怪物的区别:** 奇美拉默认任何时候都可以被链接（返回 1），不需要虚弱或眩晕状态。子类可以重写此行为（如 `ChimeraStoneSnake` 返回 0）。

#### on_chain_attached 修复

```gdscript
func on_chain_attached(slot: int) -> void:
    super.on_chain_attached(slot)
    # 关键修复：确保 _player 引用正确设置
    if _player == null:
        if _linked_player != null and is_instance_valid(_linked_player):
            _player = _linked_player as Node2D
        else:
            var players = get_tree().get_nodes_in_group("player")
            if not players.is_empty():
                _player = players[0] as Node2D
```

这里有一个重要的修复：确保再次链接时 `_player` 引用不会为空，通过多级回退策略获取玩家引用。

### 分解机制 (CHIMERA_CHIMERA 限定)

当 `origin_type == CHIMERA_CHIMERA` 的奇美拉断开锁链时，会自动分解为其组成部分。

#### 触发条件

```gdscript
func on_chain_detached(slot: int) -> void:
    var was_linked = is_linked() and get_linked_slot() == slot
    super.on_chain_detached(slot)
    if was_linked and not is_linked():
        _player = null
        if origin_type == ChimeraOriginType.CHIMERA_CHIMERA:
            _decompose()  # 触发分解
```

#### 分解过程

```gdscript
func _decompose() -> void:
    if source_scenes.is_empty():
        return
    var count := source_scenes.size()
    var positions := _calculate_decompose_positions(count)
    for i in range(count):
        var entity = source_scenes[i].instantiate()
        if entity is Node2D:
            entity.global_position = positions[i]
        get_parent().add_child(entity)
    queue_free()  # 分解后自身销毁
```

#### 位置计算

分解产物的生成位置：
- **2 个产物:** 以基准点（优先使用玩家位置）左右各偏移 80px。若位置被阻挡则向上偏移
- **其他数量:** 均匀分布在基准点周围 80px 半径的圆上

```gdscript
# 2个产物的位置
left  = base + Vector2(-80, 0)   # 或 (-40, -50) 如果被阻挡
right = base + Vector2(80, 0)    # 或 (40, -50) 如果被阻挡

# N个产物的位置
offset = Vector2(cos(angle), sin(angle)) * 80.0  # 均匀圆形分布
```

> **注意:** `_is_position_blocked()` 当前始终返回 `false`，物理检测尚未实现 (TODO)。

### 玩家互动接口

```gdscript
func on_player_interact(_player_ref: Player) -> void:
    pass  # 基类为空，子类重写
```

这是一个预留的核心接口。当玩家对链接的奇美拉执行互动操作时调用。不同的奇美拉子类通过重写此方法提供不同的能力效果。

---

## 具体奇美拉类型

### ChimeraA

**文件:** `scene/chimera_a.gd`
**class_name:** `ChimeraA`

标准奇美拉，可被链接并跟随玩家。提供回血互动能力。

| 属性 | 值 |
|------|-----|
| `species_id` | `chimera_a` |
| `attribute_type` | `NORMAL` |
| `size_tier` | `MEDIUM` |
| `follow_player_when_linked` | `true`（继承默认值）|

**互动效果:**

```gdscript
func on_player_interact(p: Player) -> void:
    if p.has_method("heal"):
        p.call("heal", 1)
    print("[ChimeraA] 玩家互动：回复1心")
```

玩家互动时回复 1 点 HP。

### ChimeraStoneSnake

**文件:** `scene/chimera_stone_snake.gd`
**class_name:** `ChimeraStoneSnake`

石蛇奇美拉，一种攻击型奇美拉。**无法被玩家链接**，会主动攻击范围内的玩家。

| 属性 | 值 |
|------|-----|
| `species_id` | `chimera_stone_snake` |
| `attribute_type` | `NORMAL` |
| `size_tier` | `MEDIUM` |
| `follow_player_when_linked` | `false` |
| `can_be_attacked` | `false` |
| `is_flying` | `false`（陆行）|

**攻击参数:**

```gdscript
@export var attack_range: float = 200.0       # 攻击范围
@export var attack_cooldown: float = 1.0       # 攻击间隔（秒）
@export var bullet_speed: float = 400.0        # 子弹速度
@export var bullet_stun_time: float = 0.5      # 命中后僵直时间
```

**锁链交互:**

```gdscript
func on_chain_hit(_player_ref: Node, _slot: int) -> int:
    return 0  # 始终无法链接
```

**攻击逻辑:**
1. 通过 `DetectionArea` (Area2D) 检测玩家进入范围
2. 玩家进入范围时立即开始攻击（`_attack_timer = 0.0`）
3. 每隔 `attack_cooldown` 秒发射一枚子弹
4. 子弹朝玩家方向飞行，命中后对玩家施加僵直（`Player.apply_stun`），不造成伤害

**子弹实现:**

子弹通过动态创建 `Area2D` 节点实现，包含：
- `Sprite2D`（缩放 0.3x）
- `CircleShape2D`（半径 10px）
- 动态附加的 GDScript 脚本（控制飞行和碰撞）
- 3 秒后自动销毁（`lifetime = 3.0`）
- `collision_mask = 2`（仅与 PlayerBody 层碰撞）

### ChimeraTemplate

**文件:** `scene/chimera_template.gd`
**class_name:** `ChimeraTemplate`

奇美拉创建模板。不用于实际游戏，而是作为创建新奇美拉类型的参考模板。

**创建新奇美拉的步骤:**
1. 复制此脚本，重命名为 `chimera_xxx.gd`
2. 修改 `class_name` 为 `ChimeraXxx`
3. 在 `_ready()` 中设置 `species_id`、`attribute_type` 等属性
4. 根据需要重写行为方法
5. 复制 `ChimeraTemplate.tscn`，挂载新脚本，设置贴图和碰撞体
6. 在 `fusion_registry.gd` 中注册此奇美拉为融合产物

---

## 怪物属性速查表

| 怪物 | `species_id` | 属性 | 型号 | HP | `weak_hp` | 泯灭次数 | 速度 | 移动方式 | 特殊机制 |
|------|-------------|------|------|-----|-----------|----------|------|----------|----------|
| MonsterWalk | `walk_dark` | DARK | SMALL | 5 | 1 | 1 | 70 | 地面巡逻 | 碰墙转向 |
| MonsterWalkB | `walk_dark_b` | DARK | SMALL | 4 | 1 | 1 | 80 | 地面巡逻 | 紫色变种 |
| MonsterFly | `fly_light` | LIGHT | SMALL | 3 | 1 | **2** | 90 | 浮空飘动 | **显隐机制** |
| MonsterFlyB | `fly_light_b` | LIGHT | SMALL | 2 | 1 | 1 | 100 | 浮空飘动 | 金色变种 |
| MonsterNeutral | `neutral_small` | NORMAL | SMALL | 3 | 1 | 1 | 50 | 地面巡逻 | 可与任何属性融合 |
| MonsterHostile | `hostile_fail` | NORMAL | MEDIUM | 5 | **0** | 1 | 100 | 地面巡逻 | **无虚弱状态**，死亡掉治愈精灵 |
| MonsterHand | `hand_light` | LIGHT | SMALL | 3 | 1 | 1 | 100 | 浮空飘动 | 怪手 |

| 奇美拉 | `species_id` | 属性 | 型号 | 可链接 | 跟随玩家 | 特殊能力 |
|--------|-------------|------|------|--------|----------|----------|
| ChimeraA | `chimera_a` | NORMAL | MEDIUM | 是 | 是 | 互动回复1心 |
| ChimeraStoneSnake | `chimera_stone_snake` | NORMAL | MEDIUM | **否** | 否 | 发射僵直子弹 |

---

## 关键设计要点

### 1. 虚弱是击杀的唯一窗口

对于有虚弱状态的怪物（`weak_hp > 0`），普通攻击只能将 HP 打到虚弱阈值。进入虚弱后 `hp_locked = true`，只有泯灭融合才能击杀。如果玩家在虚弱眩晕时间内未能完成击杀，怪物将完全恢复。

### 2. MonsterHostile 是例外

`MonsterHostile` 设置 `weak_hp = 0`，永远不会进入虚弱状态。HP 可以被普通攻击一直减少至 0 而死亡。这是融合失败的惩罚产物，设计为需要直接战斗消灭。

### 3. 泯灭次数可配置

不同怪物可以设置不同的 `vanish_fusion_required`。`MonsterFly` 需要 2 次泯灭融合才会死亡，增加了击杀难度，与其显隐机制配合形成独特的挑战。

### 4. 锁链延长虚弱时间

每次成功的 `on_chain_attached` 都会延长虚弱/眩晕时间（增加 `weak_stun_extend_time` 即 3.0 秒）。这给予玩家更多操作空间来完成融合/击杀。

### 5. 奇美拉的链接规则不统一

不同奇美拉有不同的链接规则：
- `ChimeraA`：始终可链接（默认行为）
- `ChimeraStoneSnake`：始终不可链接（`on_chain_hit` 返回 0）
- `ChimeraTemplate` 展示了条件链接的模式

### 6. CHIMERA_CHIMERA 的分解特性

类型 3 的奇美拉（由两只奇美拉融合而成）在断链时会自动分解为原始组成部分。这为融合系统增加了策略深度。

### 7. 融合消失的统一管理

`set_fusion_vanish()` 统一在 `EntityBase` 中实现，`MonsterBase` 和 `ChimeraBase` 不再各自重复定义。保存/恢复 `collision_layer` 和 `collision_mask`，确保状态一致性。

### 8. 飞行怪的显隐与锁链

`MonsterFly` 变为不可见时会强制释放所有锁链。这意味着玩家必须在可见时间窗口内完成链接和融合操作，增加了时间压力。
