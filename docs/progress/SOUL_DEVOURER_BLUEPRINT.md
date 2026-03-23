# 《噬魂犬（Soul Devourer）工程蓝图 v0.5.4》

> 目标：把需求整理为 **AI 可直接执行** 的工程规范（Godot 4.5 + GDScript + Beehave）。
> 说明：本蓝图严格对齐"规则收口与程序修改建议（2026-03-22）"的最终裁定及后续审校反馈。
> 状态：**规则已收口，可直接落地。**

---

## v0.5.4 变更日志（对比 v0.5.3）

| 序号 | 变更 | 说明 |
|------|------|------|
| FIX-V54-01 | `cleaver_pick` 改为立即销毁目标 SoulCleaver | 该帧刀已进入噬魂犬自身动画表现，场上不再保留刀节点。撤销 v0.5.2 的"仅 claim"方案 |
| FIX-V54-02 | `knife_put_away` 改名为 `throw_cleaver` | 该动画不是"收刀"而是"甩出"，事件帧生成新 SoulCleaver 并与怪物分离 |
| FIX-V54-03 | 删除 §13.5.1.1 打断释放 claimed 逻辑 | `cleaver_pick` 已立即销毁刀，不存在"claimed 但未销毁"的孤儿节点问题 |
| FIX-V54-04 | 新增 `change_to_has_knife` 被打断时的处理 | `cleaver_pick` 前被打断→刀仍在场上（未销毁）；`cleaver_pick` 后被打断→刀已销毁，无需清理 |

| 序号 | 变更 | 说明 |
|------|------|------|
| FIX-V52-01 | ~~`cleaver_pick` 改为仅锁定~~ | **v0.5.4 已撤销**：改为立即销毁 |
| FIX-V52-02 | ~~death-rebirth 打断时释放 claimed~~ | **v0.5.4 已撤销**：立即销毁后不存在孤儿节点问题 |

## v0.5.1 变更日志（对比 v0.5）

| 序号 | 变更 | 说明 |
|------|------|------|
| ADD-V51-01 | 新增 Spine 事件 `cleaver_pick` | `normal/change_to_has_knife` 动画中"拿到刀"的精确时点。**v0.5.4 修正**：立即销毁目标 SoulCleaver |
| ADD-V51-02 | ~~新增 Spine 事件 `knife_put_away`~~ | **v0.5.4 改名为 `throw_cleaver`**：该动画是"甩出刀"而非"收刀"，事件帧生成新 SoulCleaver |
| ADD-V51-03 | 新增 §13.5 斩魂刀事件职责划分 | 拿刀/收刀/掉刀三阶段事件严格分离，含程序处理伪代码和动画完成后的状态切换时点表 |

## v0.5 变更日志（对比 v0.4）

| 序号 | 变更 | 说明 |
|------|------|------|
| FIX-V5-01 | 命中入口回归 `apply_hit()` 单入口 | FireHurtbox 是被动 Hurtbox（`monitorable=true, monitoring=false`），由项目现有命中管线路由。因为 SoulDevourer **没有身体 Hurtbox**，管线路由进来的命中天然就是 fire 命中，不需要额外区分。删除 `apply_fire_hurtbox_hit()` 和帧内标志位 |
| FIX-V5-02 | 强制隐身 light_exposure 增加 source 判定说明 | 若项目存在多种 light_exposure 来源，强制隐身期间仅 LightningFlower 来源可解除 |
| FIX-V5-03 | `_update_weak_state()` 措辞统一 | 改为单一明确指令：默认不覆写；如联调确认基类 weak 链路仍有副作用，则改为覆写空函数 |

## v0.4 变更日志（对比 v0.3）

| 序号 | 变更 | 说明 |
|------|------|------|
| FIX-V4-01 | ~~命中入口改为 FireHurtbox 直接调用~~ → v0.5 已修正 | v0.4 方案存在碰撞配置冲突，v0.5 回归标准管线 |
| FIX-V4-02 | FireHurtbox 可见性例外边界 | 补充硬规则：普通隐身→火焰可命中；death-rebirth 隐藏期→FireHurtbox 关闭不可命中 |
| FIX-V4-03 | ~~删除 `_update_weak_state()` 覆写~~ → v0.5 措辞修正 | 统一为单一指令 |
| FIX-V4-04 | 着陆锁定与 death-rebirth 排队 | 新增 `_pending_death_rebirth` 机制，landing_locked 期间不立即进入 death-rebirth，落地后统一处理 |
| FIX-V4-05 | 斩魂刀检测改为组查询 | DetectArea 不再负责感知 SoulCleaver，改用 `get_tree().get_nodes_in_group("soul_cleaver")` 查询 |
| FIX-V4-06 | 新增 `_death_rebirth_started` 防重入 | 防止复杂状态下重复触发 death-rebirth |

---

## 0. 名词归一

| 需求原词 | 工程标准名 | 备注 |
|---|---|---|
| 噬魂犬 | `SoulDevourer`（class_name） | `scene/enemies/soul_devourer/SoulDevourer.tscn` |
| 双头噬魂犬 | `TwoHeadedSoulDevourer`（class_name） | 独立 SpineSprite 实例 |
| 斩魂刀 | `SoulCleaver`（class_name） | `scene/enemies/soul_devourer/SoulCleaver.tscn` |
| 猎物组 | `"huntable_ghost"` | 绝对不要用 `"ghost"` 查猎物 |
| 斩魂刀组 | `"soul_cleaver"` | 场景对象搜索用，不走 DetectArea |

---

## 1. 与当前项目硬规则的对齐约束

1. **实体类型为 Monster**：`entity_type = EntityType.MONSTER`，继承 `MonsterBase`。
2. **属性为暗**：`attribute_type = AttributeType.DARK`。
3. **体型为 MEDIUM**：`size_tier = SizeTier.MEDIUM`。
4. **全状态不可被 chain 链接**：`on_chain_hit()` 在任意状态返回 `0`。
5. **唯一有效伤害来源只有 `ghost_fist`**。
6. **只有 `ghost_fist` 命中 `FireHurtbox` 才算有效命中**。SoulDevourer 没有身体 Hurtbox，`FireHurtbox` 是唯一 EnemyHurtbox 层节点，因此项目命中管线路由进来的命中天然就是 fire 命中。
7. **命中入口为标准 `apply_hit()`**：由项目现有命中管线路由调用（攻击方 Hitbox 检测到 FireHurtbox → 管线传递 HitData）。FireHurtbox 本身是被动 Hurtbox（`monitorable=true, monitoring=false`），不自己收 `area_entered`。
8. **无 stun**：覆写 `apply_stun()` 直接 return，所有 stun 时间归零。
9. **weak → death-rebirth**：唯一入口在 `apply_hit()` 中。默认不覆写基类 `_update_weak_state()`；如联调确认基类 weak 链路仍有副作用，则改为覆写空函数。
10. **猎物组为 `huntable_ghost`**。
11. **斩魂刀查找用 `"soul_cleaver"` 组查询**，不走 DetectArea。
12. **LightReceiver 与 FireHurtbox 分离**。
13. **强制隐身覆写基类光照接口**。
14. **Beehave 条件无副作用**。D-16 合规。冷却用 Blackboard 时间戳。
15. **Spine API `has_method()` 探测**。信号+轮询双保险。禁止 `clear_track()`。
16. **攻击判定由 Spine 事件驱动**。
17. **双头噬魂犬独立场景**，不走 FusionRegistry。

---

## 2. 基础信息

### 2.1 噬魂犬

| 字段 | 值 |
|------|-----|
| 代码名 | `SoulDevourer` |
| 属性 | DARK |
| 体型 | MEDIUM |
| HP / max_hp | **3** |
| weak_hp | **1** |
| hit_stun_time | **0.0** |
| stun_duration | **0.0** |
| healing_burst_stun_time | **0.0** |
| 材质节点 | SpineSprite |

### 2.2 双头噬魂犬

| 字段 | 值 |
|------|-----|
| 代码名 | `TwoHeadedSoulDevourer` |
| 类型 | 特殊实体（不继承 MonsterBase） |
| HP | 无（无敌） |

### 2.3 斩魂刀

| 字段 | 值 |
|------|-----|
| 代码名 | `SoulCleaver` |
| 组 | `"soul_cleaver"` |

---

## 3. 核心状态字段

```gdscript
# ===== 行为 =====
var _aggro_mode: bool = false
var _is_full: bool = false
var _has_knife: bool = false
var _is_floating_invisible: bool = false
var _forced_invisible: bool = false

# ===== death-rebirth =====
var _death_rebirth_started: bool = false   # ★ 防重入 guard
var _is_dead_hidden: bool = false          # death 播完后的隐藏等待期
var _is_respawning: bool = false           # born 动画播放中

# ===== 锁定 =====
var _landing_locked: bool = false
var _pending_death_rebirth: bool = false   # ★ 着陆期间命中排队
var _merging: bool = false
var _force_separate: bool = false

# ===== 目标 =====
var _current_target_ghost: Node = null
var _current_target_cleaver: Node = null

# ===== 辅助 =====
var _spawn_point: Vector2
var _knife_attack_count: int = 0
```

---

## 4. 场景节点树

### 4.1 噬魂犬

```
SoulDevourer (CharacterBody2D)
├── SpineSprite
├── CollisionShape2D               # 身体碰撞体（EnemyBody）
├── FireHurtbox (Area2D)           # ★ 唯一受击弱点 — 跟随 Spine "fire" 骨骼
│   └── CollisionShape2D           #   被动 Hurtbox（monitorable=true, monitoring=false）
                                    #   由项目命中管线路由 HitData → apply_hit()
├── DetectArea (Area2D)            # 玩家/幽灵空间感知（不负责斩魂刀检测）
│   └── CollisionShape2D
├── AttackHitbox (Area2D)          # 攻击判定
│   └── CollisionShape2D
├── LightBeamHitbox (Area2D)       # 光炮判定
│   └── CollisionShape2D
├── LightReceiver (Area2D)         # ★ 光照感知（与 FireHurtbox 分离）
│   └── CollisionShape2D
├── MergeDetectArea (Area2D)       # 合体检测
│   └── CollisionShape2D
├── Mark2D (Marker2D)              # has_knife weak 时生成斩魂刀
├── GroundRaycast (RayCast2D)      # 地面检测
└── BeehaveTree
```

#### 4.1.1 FireHurtbox 骨骼跟随

```gdscript
func _sync_fire_hurtbox() -> void:
    var bone_pos := _get_bone_world_pos("fire")
    if bone_pos != Vector2.ZERO:
        $FireHurtbox.position = to_local(bone_pos)
```

#### 4.1.2 LightReceiver 与 FireHurtbox 分离

```gdscript
# _ready() 中必须显式设置
light_receiver_path = NodePath("LightReceiver")
```

#### 4.1.3 火焰独立显示

- fire 插槽 alpha 始终 = 1.0，不受光照/闪电影响
- 隐身时仅隐藏身体插槽，fire 保持显示

#### 4.1.4 FireHurtbox 可见性规则（FIX-V4-02 例外边界）

| 状态 | FireHurtbox | 说明 |
|------|-------------|------|
| 正常显现 | **开启** | 可被命中 |
| 普通隐身（`_is_floating_invisible`） | **开启** | 火焰始终可被命中 |
| 强制隐身（`_forced_invisible`） | **开启** | 火焰始终可被命中 |
| **death-rebirth 隐藏期**（`_is_dead_hidden`） | **关闭** | 不可被命中，不接受任何输入 |
| **重生中**（`_is_respawning`） | **关闭** | born 动画期间不可被命中 |

> **硬规则**：只有 `_is_dead_hidden == true` 或 `_is_respawning == true` 时 FireHurtbox 才关闭。其余所有状态（包括隐身）火焰始终可被命中。

### 4.2 双头噬魂犬

```
TwoHeadedSoulDevourer (CharacterBody2D)
├── SpineSprite
├── CollisionShape2D
├── DualBeamHitboxLeft (Area2D)
├── DualBeamHitboxRight (Area2D)
├── SplitMarkLeft (Marker2D)
├── SplitMarkRight (Marker2D)
└── GroundRaycast (RayCast2D)
```

### 4.3 斩魂刀

```
SoulCleaver (Area2D)
├── CollisionShape2D
└── Sprite2D
```

```gdscript
class_name SoulCleaver

var owner_instance_id: int = 0
var claimed: bool = false
var life_time: float = 12.0

func _ready() -> void:
    add_to_group("soul_cleaver")   # ★ 噬魂犬通过组查询找刀
```

**硬规则**：
1. 同一时刻只能被一只犬锁定（`claimed = true`）
2. 掉刀时记录 `owner_instance_id`
3. 原 owner 存在且未持刀 → 优先拾取自己掉的刀
4. 12 秒无人拾取 → `queue_free()`
5. `change_to_has_knife` 播完后才销毁刀
6. 中途进入 death-rebirth → 不销毁刀

---

## 5. 碰撞层配置

### 5.1 噬魂犬

```gdscript
# === CharacterBody2D ===
collision_layer = 4   # EnemyBody(3)
collision_mask = 1     # World(1)

# === FireHurtbox (Area2D) — 弱点（被动 Hurtbox）===
collision_layer = 8   # EnemyHurtbox(4)
collision_mask = 0    # 不主动检测任何层
# monitorable = true（被攻击方 Hitbox 检测到）
# monitoring = false（自己不检测）
# ★ 攻击方（ghost_fist）的 Hitbox 扫描 EnemyHurtbox 层 → 检测到 FireHurtbox
# → 项目命中管线将 HitData 路由到 SoulDevourer.apply_hit()

# === LightReceiver (Area2D) — 光照（与 FireHurtbox 分离！）===
collision_layer = 16  # ObjectSense(5)
collision_mask = 16   # ObjectSense(5)

# === DetectArea (Area2D) — 玩家/幽灵空间感知 ===
collision_layer = 0
collision_mask = 2 | 4  # PlayerBody(2) + EnemyBody(3)
# ★ 不负责斩魂刀检测（斩魂刀用组查询）

# === AttackHitbox / LightBeamHitbox ===
collision_layer = 32  # hazards(6)
collision_mask = 2     # PlayerBody(2)

# === MergeDetectArea ===
collision_layer = 0
collision_mask = 4     # EnemyBody(3)

# ❌ 不设置 ChainInteract(7)
```

---

## 6. 命中入口（FIX-V5-01 重写）

### 6.1 设计原理

SoulDevourer **没有身体 Hurtbox 节点**。`FireHurtbox` 是场景中**唯一**处于 `EnemyHurtbox(4)` 层的 Area2D。因此项目现有命中管线（攻击方 Hitbox 扫描 EnemyHurtbox 层 → 检测到 FireHurtbox → 路由 HitData 到实体 `apply_hit()`）天然保证了：**凡是走管线进来的命中，就一定是命中了火焰弱点**。

不需要额外的 `apply_fire_hurtbox_hit()` 入口，也不需要帧内标志位，也不需要 FireHurtbox 自己收 `area_entered`。

### 6.2 `on_chain_hit()` — 全状态返回 0

```gdscript
func on_chain_hit(_player: Node, _slot: int) -> int:
    return 0
```

### 6.3 `apply_hit()` — 唯一有效命中入口

```gdscript
func apply_hit(hit: HitData) -> bool:
    if hit == null:
        return false
    if _death_rebirth_started:
        return false
    if hit.weapon_id != &"ghost_fist":
        return false

    # --- 有效命中（必然是 FireHurtbox，因为没有身体 Hurtbox）---
    _aggro_mode = true
    hp = max(hp - hit.damage, 0)
    _flash_once()

    if hp <= weak_hp:
        if _landing_locked:
            _pending_death_rebirth = true   # 着陆期间排队
        else:
            _enter_death_rebirth_flow()
    return true
```

### 6.4 `apply_stun()` — 空操作

```gdscript
func apply_stun(_seconds: float, _do_flash: bool = true) -> void:
    return
```

### 6.5 `_update_weak_state()` 处理（FIX-V5-03 措辞统一）

death-rebirth 的唯一入口在 `apply_hit()` 中。

**默认不覆写** `_update_weak_state()`。基类 weak 链路因为 `_death_rebirth_started` guard 的存在，不会产生重复触发。如联调确认基类 `_update_weak_state()` 仍有无法绕过的副作用（如直接修改 `weak` 标志或调用 `_restore_from_weak()`），则改为覆写空函数：

```gdscript
func _update_weak_state() -> void:
    pass  # 噬魂犬不走基类 weak 链路
```

---

## 7. Death-Rebirth 流程

### 7.1 流程

```
有效 ghost_fist 命中 FireHurtbox → hp <= weak_hp
→ （若 _landing_locked → _pending_death_rebirth = true → 等落地）
→ _enter_death_rebirth_flow()
→ _death_rebirth_started = true
→ 锁死行为树 / 关闭攻击 / 停止移动
→ 若 _has_knife：
  → 播放 has_knife/weak
  → Spine 事件 spawn_cleaver → Mark2D 生成 SoulCleaver（唯一生成场景刀的时点）
  → animation_completed → _has_knife = false
→ 播放 death
→ death 完成
→ _finish_death_and_hide()
  ├─ _is_dead_hidden = true
  ├─ 隐藏节点 / 关闭所有碰撞（含 FireHurtbox）/ 停止 AI
  └─ 启动 10 秒计时器
→ 10 秒后
→ _respawn_from_spawn_point()
  ├─ 移动到 _spawn_point
  ├─ _is_respawning = true
  └─ 播放 normal/born
→ born 完成
→ _reset_runtime_state_after_respawn()
  ├─ hp = max_hp
  ├─ 保留 `_aggro_mode`
  ├─ 清空 full/knife/invisible/landing/death_rebirth 等临时状态
  ├─ 恢复显示 / 碰撞 / AI
  └─ → normal/idle
```

### 7.2 着陆锁定排队（FIX-V4-04）

```gdscript
# 着陆完成后检查排队
func _on_landing_complete() -> void:
    _landing_locked = false
    if _pending_death_rebirth:
        _pending_death_rebirth = false
        _enter_death_rebirth_flow()
```

> **硬规则**：`_landing_locked == true` 期间受到有效命中 → 正常扣血 → 不立即进 death-rebirth → 置 `_pending_death_rebirth = true` → fall_down 完成后统一处理。

### 7.3 防重入（FIX-V4-06）

```gdscript
func _enter_death_rebirth_flow() -> void:
    if _death_rebirth_started:
        return  # 防重入
    _death_rebirth_started = true
    # ... 后续流程
```

### 7.4 实现接口

```gdscript
func _enter_death_rebirth_flow() -> void
func _finish_death_and_hide() -> void
func _respawn_from_spawn_point() -> void
func _reset_runtime_state_after_respawn() -> void
```

### 7.5 禁止事项

- 不要进入 `weak_loop`
- 不要让玩家链上去
- 不要沿用 `MonsterBase._restore_from_weak()` / `weak_stun_t`
- 不要在 death 后 `queue_free()`

---

## 8. 显隐系统

### 8.1 基础机制

与 MonsterFly 一致：`light_counter` → `visible_time`。

### 8.2 火焰独立显示

fire 插槽始终 alpha = 1.0。FireHurtbox 启闭规则见 §4.1.4 表格。

### 8.3 隐身悬浮 vs 显现落地

隐身：悬浮、`collision_mask` 清除 World(1)。
显现：恢复重力、恢复 World、**不与 platform 碰撞**。

### 8.4 着陆序列

```
显现 → fall_loop → GroundRaycast 命中 → fall_down → 完毕 → _on_landing_complete()
```

`_landing_locked = true` 期间禁止行为插入。命中排队到落地后处理（§7.2）。

### 8.5 强制隐身覆写基类光照接口（FIX-V5-02 增加 source 判定说明）

```gdscript
func _on_thunder_burst(add_seconds: float) -> void:
    if _forced_invisible:
        return  # thunder 不能打断强制隐身
    super._on_thunder_burst(add_seconds)

func on_light_exposure(remaining_time: float, source: Node = null) -> void:
    if _forced_invisible:
        # ★ 强制隐身期间仅 LightningFlower 可解除
        if source is LightningFlower:
            _forced_invisible = false
            _is_floating_invisible = false
            _begin_landing_sequence_from_visible_recover(remaining_time)
        # 非 LightningFlower 来源：忽略
        return
    super.on_light_exposure(remaining_time, source)
```

> **source 参数说明**：若项目当前 `on_light_exposure()` 签名不含 source 参数，需扩展签名或在调用侧传递来源标识。核心规则不可动摇：**强制隐身期间，thunder 忽略，仅 LightningFlower 可解除**。若项目中存在其他 `light_exposure` 来源（非 thunder、非 LightningFlower），默认在强制隐身期间按忽略处理，后续根据设计需要逐个决定。

---

## 9. 目标查找

### 9.1 猎物

```gdscript
func _find_nearest_huntable_ghost() -> Node2D:
    var ghosts := get_tree().get_nodes_in_group("huntable_ghost")
    # 过滤：可见 + 有效 + 非 dying + 非 being_hunted
    ...
```

### 9.2 斩魂刀（FIX-V4-05 改为组查询）

```gdscript
func _find_nearest_cleaver() -> SoulCleaver:
    var cleavers := get_tree().get_nodes_in_group("soul_cleaver")
    # 过滤：unclaimed 或 owner 是自己
    # 优先自己掉落的（owner_instance_id 匹配）
    ...
```

> **不走 DetectArea**。DetectArea 只负责玩家/幽灵空间感知。斩魂刀用组查询，与 huntable_ghost 风格一致。

---

## 10. 主动攻击模式

### 10.0 触发

`_aggro_mode = true` 在 `apply_hit()` 中设置（仅当 ghost_fist 有效命中 FireHurtbox 时）。

### 10.1 优先级 1：斩魂刀拾取

条件：`_find_nearest_cleaver()` 有结果，且技能 CD ready（5s）。

**事件驱动流程**：
```
[移动到最近 SoulCleaver] → [播放 normal/change_to_has_knife]
  │
  ├─ Spine 事件 cleaver_pick 触发
  │   → 立即 `_current_target_cleaver.queue_free()`（刀已进入噬魂犬动画表现）
  │   → 持刀视觉从此帧开始成立
  │
  ├─ cleaver_pick 之前被有效命中 → death-rebirth（刀仍在场上，未销毁）
  ├─ cleaver_pick 之后被有效命中 → death-rebirth（刀已销毁，无需清理）
  │
  └─ animation_completed
      → _has_knife = true
      → 切换到 has_knife/ 文件夹
```

### 10.2 优先级 2：has_knife 冲刺攻击

条件：`_has_knife == true`。

**两次冲刺后甩刀流程**：
```
[冲刺×2 完毕] → [播放 has_knife/change_to_normal]
  │
  ├─ Spine 事件 throw_cleaver 触发
  │   → 在生成点实例化新 SoulCleaver（可赋予抛出方向/初速度）
  │   → 关闭持刀视觉
  │   → _has_knife = false（从此帧开始不再持刀）
  │
  └─ animation_completed
      → 切换到 normal/ 文件夹
      → 技能进入 CD 5s
```

### 10.3 优先级 3：光炮（full 状态）

条件：`_aggro_mode == true && _is_full == true`。

### 10.4 优先级 4：no_full 补充猎杀

条件：`_aggro_mode == true && _is_full == false` 且 `huntable_ghost` 存在。
非 aggro 情况不走这一支，而是走 §14 行为树里的 `Cond_NotAggroAndGhostVisible` 被动猎杀分支。

### 10.5 强制隐身（idle 状态下玩家 < 100px）

详见 §8.5。

### 10.6 所有攻击行为中断规则

一旦执行，除被有效命中触发 death-rebirth 外不可中断。每个移动行为有超时兜底。

---

## 11. 双文件夹动画系统

`_has_knife == false` → `normal/`；`_has_knife == true` → `has_knife/`。

```gdscript
func _get_anim_prefix() -> String:
    return "has_knife/" if _has_knife else "normal/"

func _play_prefixed_anim(anim_base: StringName, loop: bool) -> void:
    _play_anim(StringName(_get_anim_prefix() + String(anim_base)), loop)
```

---

## 12. 行为中断矩阵

| 当前行为 | 玩家贴脸 | 目标消失 | 被有效命中（fire） | 受光照 | 超时 |
|---|---|---|---|---|---|
| hunt ghost | 不切 | 取消→idle | **death-rebirth**（或排队） | 正常 | 4.0s 退出 |
| move to cleaver | 不切 | cleaver消失→idle | **death-rebirth**（或排队） | 正常 | 5.0s 退出 |
| knife_attack_run | 不切 | — | **death-rebirth** | 不切 | 位移耗尽/2.2s |
| light beam | 不切 | — | **death-rebirth** | 不切 | 动画结束 |
| landing | 不切 | 不切 | **排队** `_pending_death_rebirth` | 不切 | 动画结束 |
| forced invisible | 保持150px | — | — | 雷花唤醒 | 5.0s后恢复 |
| death-rebirth | — | — | 忽略 | 忽略 | 10.0s后born |

---

## 13. Spine 动画清单

### 13.1 normal/ 文件夹

| 动画名 | 循环 | 轨道 | 说明 |
|--------|------|------|------|
| `normal/idle` | 是 | 0 | 地面待机 |
| `normal/run` | 是 | 0 | 地面奔跑 |
| `normal/fall_loop` | 是 | 0 | 空中下落循环 |
| `normal/fall_down` | 否 | 0 | 着地 |
| `normal/huntting_succeed` | 否 | 0 | 猎杀成功（吞食完毕收束） |
| `normal/huntting` | 是 | 0 | 猎杀进行中（低姿态追猎/带捕食意图移动，不等同于 run） |
| `normal/light_beam` | 否 | 0 | 光炮；含 `atk_hit_on`/`atk_hit_off` |
| `normal/change_to_has_knife` | 否 | 0 | 拾取斩魂刀；含 `cleaver_pick` 事件 |
| `normal/forced_invisible` | 否 | 0 | 强制隐身 |
| `normal/float_idle` | 是 | 0 | 漂浮待机 |
| `normal/float_move` | 是 | 0 | 漂浮移动 |
| `normal/death` | 否 | 0 | 死亡 |
| `normal/born` | 否 | 0 | 重生 |

### 13.2 has_knife/ 文件夹

| 动画名 | 循环 | 轨道 | 说明 |
|--------|------|------|------|
| `has_knife/idle` | 是 | 0 | 持刀待机 |
| `has_knife/run` | 是 | 0 | 持刀奔跑 |
| `has_knife/knife_attack_run` | 否 | 0 | 冲刺甩刀；含 `atk_hit_on`/`atk_hit_off` |
| `has_knife/change_to_normal` | 否 | 0 | 甩出斩魂刀；含 `throw_cleaver` 事件（生成新刀） |
| `has_knife/weak` | 否 | 0 | 持刀虚弱→结尾 `spawn_cleaver` |

### 13.3 双头噬魂犬

| 动画名 | 循环 | 轨道 | 说明 |
|--------|------|------|------|
| `enter` | 否 | 0 | 合体出现 |
| `fall_loop` | 是 | 0 | 空中下坠 |
| `land` | 否 | 0 | 落地 |
| `dual_beam` | 否 | 0 | 双向光炮 |
| `split` | 否 | 0 | 分离 |

### 13.4 Spine 事件

| 事件名 | 所在动画 | 作用 |
|--------|---------|------|
| `atk_hit_on` | `normal/light_beam`, `has_knife/knife_attack_run`, `dual_beam` | 启用 Hitbox |
| `atk_hit_off` | 同上 | 禁用 Hitbox |
| `cleaver_pick` | `normal/change_to_has_knife` | 立即销毁目标 SoulCleaver（刀进入噬魂犬动画表现），持刀视觉成立 |
| `throw_cleaver` | `has_knife/change_to_normal` | 甩出刀：生成新 SoulCleaver 并与怪物分离，关闭持刀视觉，`_has_knife = false` |
| `spawn_cleaver` | `has_knife/weak` | 受击掉刀：在 Mark2D 位置生成新 SoulCleaver |

### 13.5 斩魂刀事件职责划分

三个斩魂刀相关事件各自职责严格分离，**不可混用**：

| 阶段 | 动画 | 事件 | 做什么 | 不做什么 |
|------|------|------|--------|---------|
| **拿刀** | `normal/change_to_has_knife` | `cleaver_pick` | 立即 `queue_free()` 目标 SoulCleaver；持刀视觉从此帧成立 | 不切换 `_has_knife` 状态（等 animation_completed） |
| **甩刀** | `has_knife/change_to_normal` | `throw_cleaver` | 在生成点实例化新 SoulCleaver（可赋抛出方向/初速度）；关闭持刀视觉；`_has_knife = false` | — |
| **掉刀** | `has_knife/weak` | `spawn_cleaver` | 在 Mark2D 实例化新 SoulCleaver | — |

> **`throw_cleaver` 和 `spawn_cleaver` 都会生成新 SoulCleaver**，但场景不同：前者是主动甩出（两次冲刺后），后者是受击掉落（death-rebirth 前）。

#### 13.5.1 `cleaver_pick` 程序处理

```gdscript
func _on_spine_event_cleaver_pick() -> void:
    if _current_target_cleaver == null:
        return
    if is_instance_valid(_current_target_cleaver):
        _current_target_cleaver.queue_free()   # 立即销毁，刀已进入动画表现
    _current_target_cleaver = null
    # 持刀视觉从此帧开始成立
    # _has_knife = true 等 animation_completed
```

#### 13.5.1.1 `change_to_has_knife` 被打断时的处理

两种情况：

| `cleaver_pick` 是否已触发 | death-rebirth 打断后 | 说明 |
|--------------------------|---------------------|------|
| **未触发** | 刀仍在场上，未被销毁，`_current_target_cleaver` 仍有效 | 释放 `_current_target_cleaver = null`，刀自然可被其他单位拾取 |
| **已触发** | 刀已被 `queue_free()` 销毁，无需清理 | `_current_target_cleaver` 已为 null |

```gdscript
# 在 _enter_death_rebirth_flow() 中：
_current_target_cleaver = null   # 无论哪种情况都安全清空引用
```

#### 13.5.2 `throw_cleaver` 程序处理

```gdscript
func _on_spine_event_throw_cleaver() -> void:
    var cleaver_scene := preload("res://scene/enemies/soul_devourer/SoulCleaver.tscn")
    var cleaver := cleaver_scene.instantiate()
    cleaver.global_position = $Mark2D.global_position
    cleaver.owner_instance_id = get_instance_id()
    # 可选：赋予抛出方向/初速度
    # cleaver.velocity = Vector2(facing_direction * throw_speed, -throw_arc)
    get_parent().add_child(cleaver)

    # 关闭持刀视觉
    _has_knife = false
    # normal/ 文件夹切换等 animation_completed
```

#### 13.5.3 `spawn_cleaver` 程序处理（保持不变）

```gdscript
func _on_spine_event_spawn_cleaver() -> void:
    var cleaver_scene := preload("res://scene/enemies/soul_devourer/SoulCleaver.tscn")
    var cleaver := cleaver_scene.instantiate()
    cleaver.global_position = $Mark2D.global_position
    cleaver.owner_instance_id = get_instance_id()
    get_parent().add_child(cleaver)
```

#### 13.5.4 动画完成后的状态切换时点

| 动画 | animation_completed 后做什么 |
|------|---------------------------|
| `normal/change_to_has_knife` | `_has_knife = true` → 切换到 has_knife/ 文件夹 |
| `has_knife/change_to_normal` | 切换到 normal/ 文件夹 → 技能进入 CD（`_has_knife` 已在 `throw_cleaver` 事件中置 false） |
| `has_knife/weak` | `_has_knife = false` → 进入 death-rebirth 流程 |

---

## 14. 行为树（Beehave）

```
BeehaveTree (process_thread: PHYSICS)
└── SelectorReactiveComposite
    │
    ├── Seq [death-rebirth 锁定]                          # P0
    │   ├── Cond: cond_death_rebirth_active
    │   └── Act: act_death_rebirth_flow
    │
    ├── Seq [着陆锁定]                                    # P1
    │   ├── Cond: cond_landing_locked
    │   └── Act: act_landing_sequence
    │
    ├── Seq [强制分离]                                    # P2
    │   ├── Cond: cond_force_separate
    │   └── Act: act_separate_move
    │
    ├── Seq [合体移动]                                    # P3
    │   ├── Cond: cond_merging
    │   └── Act: act_move_to_partner
    │
    ├── Seq [漂浮隐身]                                    # P4
    │   ├── Cond: cond_floating_invisible
    │   └── SelectorComposite
    │       ├── Seq [合体检查]
    │       │   ├── Cond: cond_merge_possible
    │       │   └── Act: act_start_merge
    │       └── Act: act_float_maintain_distance
    │
    ├── Seq [强制隐身触发]                                # P5
    │   ├── Cond: cond_player_too_close_and_idle
    │   └── Act: act_forced_invisible_sequence
    │
    ├── Seq [斩魂刀拾取]                                  # P6
    │   ├── Cond: cond_aggro_and_cleaver_available
    │   └── Act: act_pickup_cleaver
    │
    ├── Seq [has_knife 冲刺]                              # P7
    │   ├── Cond: cond_has_knife
    │   └── Act: act_knife_attack_sequence
    │
    ├── Seq [光炮]                                        # P8
    │   ├── Cond: cond_aggro_and_full
    │   └── Act: act_light_beam_attack
    │
    ├── Seq [aggro + no_full → 猎杀]                      # P9
    │   ├── Cond: cond_aggro_not_full_huntable_exists
    │   └── Act: act_hunt_ghost
    │
    ├── Seq [被动猎杀]                                    # P10
    │   ├── Cond: cond_not_aggro_and_ghost_visible
    │   └── Act: act_hunt_ghost
    │
    └── Act: act_idle                                     # P11
```

### 14.1 关键 Action 说明

#### `act_death_rebirth_flow`
- 管理完整 death → hide → 10s → born → reset
- 内部状态枚举：`PLAY_WEAK_KNIFE, PLAY_DEATH, HIDDEN_WAIT, PLAY_BORN, DONE`
- 返回 `RUNNING` 直到 DONE

#### `act_landing_sequence`
- `FALL_LOOP → FALL_DOWN → DONE`
- DONE 时调用 `_on_landing_complete()`（含 pending death-rebirth 检查）

#### `act_hunt_ghost`
- 用 `_find_nearest_huntable_ghost()` 查找，锁定为 `_current_target_ghost`
- 朝目标移动：
  - **地面显现态**：远距离播放 `normal/run`，接近后切到 `normal/huntting`
  - **隐身悬浮态**：播放 `normal/float_move`（循环）— 不使用 `huntting`
- 每帧检查目标有效性（`_is_huntable_ghost_valid(target)`）
- 目标隐身 / 无效 / 被销毁 → 停止 `huntting` → 返回 FAILURE（回落 idle）
- 到达可吞食距离 → `ghost.start_being_hunted()` → 播放 `normal/huntting_succeed` → `_is_full = true` → SUCCESS
- 被有效命中 → death-rebirth（或 landing lock 排队）→ 不再继续 huntting
- 超时 4.0s → FAILURE

#### `act_pickup_cleaver`
- 用 `_find_nearest_cleaver()` 查找（组查询）
- 目标消失 → FAILURE
- 到达 → 播放 `normal/change_to_has_knife`
  - Spine 事件 `cleaver_pick` → 立即销毁刀，持刀视觉成立
  - animation_completed → `_has_knife = true`
- 超时 5.0s → FAILURE

---

## 15. 合体机制

场上 2 只 SoulDevourer 且都 `_is_floating_invisible` → 实例 ID 小者发起 → 双方向对方移动 → 接触 → 记录 HP → 中点生成 TwoHeadedSoulDevourer → 两只原始 SD 先隐藏并交由双头犬流程托管恢复，不在该时点直接 `queue_free()`。

双头犬：`ENTER → FALL → LAND → dual_beam → SPLIT → END`。落地后无敌。分离时还原两只犬 + HP + `_force_separate = true` → 远离 200px。

---

## 16. 临时可玩数值

```gdscript
ground_run_speed = 90.0
float_move_speed = 70.0
hp = 3
max_hp = 3
weak_hp = 1
hunt_timeout = 4.0
move_to_cleaver_timeout = 5.0
knife_attack_timeout = 2.2
forced_invisible_duration = 5.0
rebirth_delay = 10.0
attack_cooldown_has_knife = 1.0
skill_cooldown_has_knife = 5.0
skill_cooldown_light_beam = 5.0
knife_attack_overshoot = 200.0
knife_attack_trigger_dist = 40.0
light_beam_min_distance = 150.0
forced_invisible_trigger_dist = 100.0
forced_invisible_maintain_dist = 150.0
separate_distance = 200.0
merge_move_speed = 150.0
separate_speed = 120.0
fall_speed = 300.0
dual_beam_damage = 1
```

---

## 17. 已确认决策

1. 全状态不可 chain。
2. 唯一有效伤害只有 ghost_fist。
3. **`apply_hit()` 是唯一命中入口**。因为 SoulDevourer 没有身体 Hurtbox，FireHurtbox 是唯一 EnemyHurtbox 层节点，管线路由进来的命中天然就是 fire 命中。FireHurtbox 是被动 Hurtbox（`monitorable=true, monitoring=false`），不自己收 `area_entered`。
4. death-rebirth：death → hide → 10s → born → HP满。不 queue_free。
5. 无 stun。覆写 `apply_stun()` + 三个 stun 时间归零。
6. 猎物组 `huntable_ghost`。斩魂刀组 `soul_cleaver`。都用组查询，不走 DetectArea。
7. LightReceiver 与 FireHurtbox 分离。
8. **强制隐身免 thunder，仅 LightningFlower 可解除**。若存在其他 light_exposure 来源，默认忽略。覆写基类接口，含 source 判定。
9. **FireHurtbox 在普通/强制隐身时保持开启；仅 death-rebirth 隐藏期和重生中关闭**。
10. **`_update_weak_state()` 默认不覆写**；如联调确认基类 weak 链路仍有副作用，则改为覆写空函数。death-rebirth 唯一入口在 `apply_hit()`。
11. **着陆锁定期间被命中排队**：`_pending_death_rebirth = true`，落地后统一处理。
12. **`_death_rebirth_started` 防重入 guard**。
13. 属性 DARK，体型 MEDIUM。
14. SoulCleaver 独立场景，组 `soul_cleaver`。
15. 双头犬独立场景，不走 FusionRegistry。
16. 行为中断矩阵写死（§12）。
17. 所有移动有超时兜底。
18. 着陆序列和 death-rebirth 是最强锁。
19. 火焰始终显现（death-rebirth 隐藏期除外）。
20. 显现时不碰 platform。
21. 被有效命中后进入 aggro。

---

## 18. 推荐实现顺序

1. 文档同步
2. 组注册 + 节点分离（FireHurtbox/LightReceiver/SoulCleaver）
3. 命中入口（`apply_hit()` 含 ghost_fist 过滤 + `apply_stun()` 空操作 + 确认基类 weak 链路是否需要覆写空函数）
4. death-rebirth（含 `_pending_death_rebirth` 排队）
5. 强制隐身 / 着陆 / 猎杀 / has_knife / 光炮
6. SoulCleaver + TwoHeadedSoulDevourer

---

## 19. 参考文件索引

| 参考内容 | 文件 |
|---------|------|
| 幽灵被吞食接口 | `docs/WANDERING_GHOST_BLUEPRINT_v0.4.md §8` |
| 基类 | `scene/monster_base.gd`、`scene/entity_base.gd` |
| Spine API | `docs/SPINE_GODOT_LATEST_INTEGRATED_STANDARD.md` |
| Beehave（含 D-01~D-16） | `docs/BEEHAVE_REFERENCE.md` |
| 碰撞层 | `docs/A_PHYSICS_LAYER_TABLE.md` |
| 规则收口 | 《规则收口与程序修改建议（2026-03-22）》 |
