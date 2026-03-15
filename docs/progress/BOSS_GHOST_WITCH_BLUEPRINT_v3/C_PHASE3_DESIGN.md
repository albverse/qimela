# 《幽灵魔女 BossGhostWitch》工程蓝图 — C. Phase 3 设计与补充

> 本文档是三部曲的第三部，包含 Phase 2→3 过渡、Phase 3（无头骑士形态）的全部行为树、ActionLeaf、子实例、死亡流程。
> **前置依赖：必须先读 A. 全局概览。**

---

## 11. Phase 2→3 过渡流程

### 13.1 触发条件

`hp <= phase3_hp_threshold`（hp <= 10）时调用 `_begin_phase_transition(Phase.PHASE3)`。

### 13.2 过渡描述

> 石像全部碎掉，光环掉下来，鬼魂在旁边趴着，看着它们曾经的主人。突然，鬼魂被光环绑住抓住。
> 卷入到巨大的漩涡中，与墓碑的碎石合体后变成了带着镰刀的无头骑士。它拽下了光环，变成了自己巨大的镰刀。

### 13.3 过渡时序

```
1. hp_locked = true，_phase_transitioning = true
2. 中断当前 Phase 2 所有攻击流（行为树 ActWaitTransition 接管）
3. 清理 Phase 2 残留：
   → get_tree().call_group("ghost_bomb", "queue_free")
   → get_tree().call_group("ghost_wraith", "queue_free")
   → get_tree().call_group("ghost_elite", "queue_free")
   → get_tree().call_group("ghost_tug", "queue_free")
4. Boss 播放 phase2/phase2_to_phase3 动画
   → Spine 事件 "shatter"：视觉碎裂效果
   → Spine 事件 "phase3_ready"：动画末尾
5. 动画播完后：
   → 魔女动画切到 phase3/idle
   → RealHurtbox 保持绑定 hale 骨骼，保持 enabled（光环弱点延续）
   → current_phase = Phase.PHASE3
   → _phase_transitioning = false
   → hp_locked = false
   → _scythe_in_hand = true（镰刀在手）
```

---


---

## 12. Phase 3 形态概述与状态变量

**外观**：无头骑士，手持巨大镰刀（由光环变化而来）。

**核心机制**：
- `RealHurtbox` 依然绑定 hale 骨骼（头顶光环位置），是唯一弱点
- 只有 ghostfist 可造成伤害，chain 依然无效
- 镰刀可被扔出变成独立实例 `WitchScythe`；扔出期间本体禁止一切行为，只能原地待机
- 地狱之手 `HellHand` 可禁锢玩家；ghostfist 可解

**关键状态变量**（追加到 `boss_ghost_witch.gd`）：

```gdscript
# Phase 3 专用状态
var _scythe_in_hand: bool = true           # 镰刀是否在手
var _scythe_instance: Node2D = null        # 扔出的镰刀实例引用
var _scythe_recall_requested: bool = false  # 本体被打时请求镰刀回航
var _hell_hand_instance: Node2D = null     # 地狱之手实例引用
var _player_imprisoned: bool = false        # 是否检测到玩家被禁锢
```

**Phase 3 追加导出参数**：

```gdscript
# -- Phase 3 参数 --
@export var p3_move_speed: float = 120.0         # 无头骑士移动速度
@export var p3_run_speed: float = 250.0          # 奔跑斩击速度
@export var p3_dash_cooldown: float = 10.0       # 冲刺冷却
@export var p3_dash_charge_time: float = 1.0     # 冲刺蓄力时间
@export var p3_dash_speed: float = 800.0         # 冲刺速度
@export var p3_kick_cooldown: float = 1.0        # 踢人冷却
@export var p3_kick_knockback_px: float = 300.0  # 踢人弹飞距离
@export var p3_combo_cooldown: float = 1.0       # 三连斩冷却
@export var p3_combo_duration: float = 3.0       # 三连斩总持续时间
@export var p3_imprison_cooldown: float = 10.0   # 禁锢冷却
@export var p3_imprison_escape_time: float = 0.5 # 玩家逃出禁锢的窗口
@export var p3_imprison_stun_time: float = 3.0   # 禁锢僵直持续时间
@export var p3_scythe_track_interval: float = 1.0 # 镰刀每次重新检测玩家位置的间隔（秒）
@export var p3_scythe_track_count: int = 3        # 镰刀检测玩家位置的次数，完成后直线回航
@export var p3_scythe_fly_speed: float = 300.0    # 镰刀飞行速度
@export var p3_scythe_return_speed: float = 500.0 # 镰刀回航速度
@export var p3_summon_cooldown: float = 8.0      # 召唤幽灵冷却（待定）
@export var p3_summon_wave_count: int = 3        # 5秒内发动次数
@export var p3_summon_circle_count: int = 3      # 每波圆圈数（1个玩家位置+2个随机）
@export var p3_run_slash_overshoot_px: float = 200.0 # 奔跑斩击穿过玩家的距离
```

**Phase 3 追加预加载**：

```gdscript
var _witch_scythe_scene: PackedScene = preload("res://scene/enemies/boss_ghost_witch/WitchScythe.tscn")
var _hell_hand_scene: PackedScene = preload("res://scene/enemies/boss_ghost_witch/HellHand.tscn")
var _ghost_summon_scene: PackedScene = preload("res://scene/enemies/boss_ghost_witch/GhostSummon.tscn")
```

**Phase 3 追加 apply_real_damage 镰刀回航逻辑**：

```gdscript
# 在 apply_real_damage 中追加：
func apply_real_damage(amount: int) -> void:
    if hp_locked:
        _flash_once()
        return
    hp = max(hp - amount, 0)
    _flash_once()

    # Phase 3 扔镰刀期间被打 → 触发镰刀回航
    if current_phase == Phase.PHASE3 and not _scythe_in_hand:
        _scythe_recall_requested = true

    # 阶段切换检查
    if current_phase == Phase.PHASE1 and hp <= phase2_hp_threshold:
        _begin_phase_transition(Phase.PHASE2)
    elif current_phase == Phase.PHASE2 and hp <= phase3_hp_threshold:
        _begin_phase_transition(Phase.PHASE3)
    elif hp <= 0:
        _begin_death()
```

---

## 13. Phase 3 节点结构追加

以下节点追加到 `BossGhostWitch.tscn`（Phase 3 使用）：

```
BossGhostWitch (CharacterBody2D)
├── ...（Phase 1&2 节点不变）
│
├── # ===== Phase 3 追加 =====
├── KickHitbox (Area2D)             # 踢人判定，绑定 leg 骨骼
│   └── CollisionShape2D            # 默认 disabled
├── Attack1Area (Area2D)            # 三连斩第1击
│   └── CollisionShape2D            # 默认 disabled
├── Attack2Area (Area2D)            # 三连斩第2击
│   └── CollisionShape2D            # 默认 disabled
├── Attack3Area (Area2D)            # 三连斩第3击
│   └── CollisionShape2D            # 默认 disabled
└── RunSlashHitbox (Area2D)         # 奔跑斩击判定
    └── CollisionShape2D            # 默认 disabled
```

**碰撞配置（全部统一）：**

| 节点 | collision_layer | collision_mask |
|---|---|---|
| KickHitbox | `32` (hazards(6)) | `2` (PlayerBody(2)) |
| Attack1/2/3Area | `32` (hazards(6)) | `2` (PlayerBody(2)) |
| RunSlashHitbox | `32` (hazards(6)) | `2` (PlayerBody(2)) |

**骨骼绑定（_physics_process 每帧同步）：**

```gdscript
func _sync_phase3_hitboxes() -> void:
    if current_phase != Phase.PHASE3: return
    if _anim_driver == null: return
    # KickHitbox → leg 骨骼
    var leg_pos: Vector2 = _anim_driver.get_bone_world_position("leg")
    if leg_pos != Vector2.ZERO:
        _kick_hitbox.global_position = leg_pos
    # RealHurtbox → hale 骨骼（延续 Phase 2）
    var hale_pos: Vector2 = _anim_driver.get_bone_world_position("hale")
    if hale_pos != Vector2.ZERO:
        _real_hurtbox.global_position = hale_pos
```

**Boss 主脚本 Phase 3 Hitbox 管理：**

```gdscript
@onready var _kick_hitbox: Area2D = $KickHitbox
@onready var _attack1_area: Area2D = $Attack1Area
@onready var _attack2_area: Area2D = $Attack2Area
@onready var _attack3_area: Area2D = $Attack3Area
@onready var _run_slash_hitbox: Area2D = $RunSlashHitbox

func _close_all_combo_hitboxes() -> void:
    _set_hitbox_enabled(_attack1_area, false)
    _set_hitbox_enabled(_attack2_area, false)
    _set_hitbox_enabled(_attack3_area, false)

func _on_kick_hitbox_body_entered(body: Node2D) -> void:
    if not _atk_hit_window_open: return
    if body.is_in_group("player"):
        if body.has_method("apply_damage"):
            body.call("apply_damage", 1, global_position)
        if body is CharacterBody2D:
            var kb_dir := signf(body.global_position.x - global_position.x)
            if kb_dir == 0.0: kb_dir = 1.0
            body.velocity.x = kb_dir * p3_kick_knockback_px * 5.0
```

---

## 14. Phase 3 行为树

### 16.1 攻击优先级总结

```
优先级 1 (最高)：禁锢检测 → 奔跑斩击 / 追踪扔镰刀
  → 玩家被地狱之手禁锢 → Boss 立刻奔跑穿过玩家斩击
  → 若玩家在上方（跳板上）→ 跑到玩家 X 位置，向上扔镰刀追踪

优先级 2：禁锢（地狱之手）
  → 玩家在地面上 + 禁锢可用 + 镰刀在手 → 优先禁锢
  → cd=10s，全场检测

优先级 3：召唤幽灵
  → 玩家在跳板上 + ≤500px + 镰刀在手
  → 起手施法自带 combo3 攻击判定（一边召唤一边顺手砍一刀）
  → 地面出现圆圈 → 0.3s 后幽灵飞出 → 5秒内3波
  → 施法全程不可移动，维持 summon_loop 直到场上所有召唤幽灵被销毁才结束

优先级 4：冲刺
  → 300~500px + cd=10s + 镰刀在手
  → 蓄力1秒 → 快速冲刺 → 刹车减速 → 结束

优先级 5：三连斩
  → ≤200px + 玩家在上方 + 镰刀在手
  → 3秒内连续检测 attack1/attack2/attack3 区域

优先级 6：踢人
  → ≤100px + 玩家在地面 + 镰刀在手
  → cd=1s，踢中弹飞 300px

优先级 7 (兜底)：扔镰刀
  → 其他技能全部不可用 / 冷却中 + 镰刀在手
  → 无限范围，镰刀追踪砍击
  → 本体被打 → 镰刀回航 → catch_scythe → 攻击流结束 → 行为树正常重评估

镰刀不在手时的行为限制：
  → 禁止一切：不移动、不追击、不踢人、不施放任何技能
  → 仅允许：原地待机（idle_no_scythe），等待镰刀回航
  → 镰刀回航 catch_scythe 播完后 _scythe_in_hand 恢复 true，一切行为解锁

兜底：
  镰刀在手 → 缓慢向玩家移动（walk）
  镰刀不在手 → 原地待机（idle_no_scythe）
```

### 16.2 行为树结构

```
SelectorReactiveComposite [P3Selector]
│
├── SequenceReactiveComposite [P3ImprisonReactSeq]     ← 优先级 1：检测到禁锢
│   ├── CondPlayerImprisoned
│   └── SelectorComposite [P3ImprisonReactAction]
│       ├── SequenceReactiveComposite [P3RunSlashIfGround]
│       │   ├── CondPlayerOnGround
│       │   └── ActRunSlash
│       └── ActThrowScytheUpward
│
├── SequenceReactiveComposite [P3ImprisonCastSeq]      ← 优先级 2：禁锢
│   ├── CondPlayerOnGround
│   ├── CondCooldownReady (key="cd_imprison", cd=10)
│   ├── CondScytheInHand
│   └── ActCastImprison
│
├── SequenceReactiveComposite [P3SummonSeq]            ← 优先级 3：召唤幽灵
│   ├── CondPlayerOnPlatform
│   ├── CondPlayerInRange (range=500)
│   ├── CondCooldownReady (key="cd_summon", cd=p3_summon_cooldown)
│   ├── CondScytheInHand
│   └── ActSummonGhosts
│
├── SequenceReactiveComposite [P3DashSeq]              ← 优先级 4：冲刺
│   ├── CondPlayerInRange (range=500)
│   ├── InverterDecorator
│   │   └── CondPlayerInRange (range=300)
│   ├── CondCooldownReady (key="cd_dash", cd=10)
│   ├── CondScytheInHand
│   └── ActDashAttack
│
├── SequenceReactiveComposite [P3ComboSeq]             ← 优先级 5：三连斩
│   ├── CondPlayerInRange (range=200)
│   ├── CondPlayerAboveBoss
│   ├── CondCooldownReady (key="cd_combo", cd=1)
│   ├── CondScytheInHand
│   └── ActComboSlash
│
├── SequenceReactiveComposite [P3KickSeq]              ← 优先级 6：踢人
│   ├── CondPlayerInRange (range=100)
│   ├── CondPlayerOnGround
│   ├── CondCooldownReady (key="cd_kick", cd=1)
│   ├── CondScytheInHand
│   └── ActKick
│
├── SequenceReactiveComposite [P3ThrowScytheSeq]       ← 优先级 7：扔镰刀
│   ├── CondAllP3SkillsOnCooldownOrBlocked
│   ├── CondScytheInHand
│   └── ActThrowScythe
│
└── SelectorComposite [P3FallbackSelector]              ← 兜底
    ├── SequenceReactiveComposite [P3MoveIfScythe]
    │   ├── CondScytheInHand
    │   └── ActP3MoveTowardPlayer
    └── ActP3IdleNoScythe                               ← 镰刀不在手 → 原地待机
```

---

## 15. Phase 3 新增 ConditionLeaf

### CondPlayerImprisoned

```gdscript
class_name CondPlayerImprisoned extends ConditionLeaf

func tick(actor: Node, _bb: Blackboard) -> int:
    var boss := actor as BossGhostWitch
    if boss == null: return FAILURE
    return SUCCESS if boss._player_imprisoned else FAILURE
```

### CondPlayerOnGround

```gdscript
class_name CondPlayerOnGround extends ConditionLeaf

@export var y_threshold: float = 50.0

func tick(actor: Node, _bb: Blackboard) -> int:
    var boss := actor as BossGhostWitch
    if boss == null: return FAILURE
    var player: Node2D = boss.get_priority_attack_target()
    if player == null: return FAILURE
    if player is CharacterBody2D:
        var p := player as CharacterBody2D
        if p.is_on_floor():
            var y_diff := abs(p.global_position.y - actor.global_position.y)
            if y_diff <= y_threshold:
                return SUCCESS
    return FAILURE
```

### CondPlayerOnPlatform

```gdscript
class_name CondPlayerOnPlatform extends ConditionLeaf

@export var y_threshold: float = 50.0

func tick(actor: Node, _bb: Blackboard) -> int:
    var boss := actor as BossGhostWitch
    if boss == null: return FAILURE
    var player: Node2D = boss.get_priority_attack_target()
    if player == null: return FAILURE
    if player is CharacterBody2D:
        var p := player as CharacterBody2D
        if p.is_on_floor():
            var y_diff := actor.global_position.y - p.global_position.y
            if y_diff > y_threshold:
                return SUCCESS
    return FAILURE
```

### CondPlayerAboveBoss

```gdscript
class_name CondPlayerAboveBoss extends ConditionLeaf

@export var y_threshold: float = 30.0

func tick(actor: Node, _bb: Blackboard) -> int:
    var boss := actor as BossGhostWitch
    if boss == null: return FAILURE
    var player: Node2D = boss.get_priority_attack_target()
    if player == null: return FAILURE
    var y_diff := actor.global_position.y - player.global_position.y
    return SUCCESS if y_diff > y_threshold else FAILURE
```

### CondScytheInHand

```gdscript
class_name CondScytheInHand extends ConditionLeaf

func tick(actor: Node, _bb: Blackboard) -> int:
    var boss := actor as BossGhostWitch
    if boss == null: return FAILURE
    return SUCCESS if boss._scythe_in_hand else FAILURE
```

### CondAllP3SkillsOnCooldownOrBlocked

```gdscript
class_name CondAllP3SkillsOnCooldownOrBlocked extends ConditionLeaf

func tick(actor: Node, blackboard: Blackboard) -> int:
    var actor_id := str(actor.get_instance_id())
    var now_ms: float = Time.get_ticks_msec()
    var keys := ["cd_imprison", "cd_summon", "cd_dash", "cd_combo", "cd_kick"]
    for key in keys:
        var end_time: float = blackboard.get_value(key, 0.0, actor_id)
        if now_ms >= end_time:
            return FAILURE
    return SUCCESS
```

---

## 16. Phase 3 ActionLeaf 详细设计

### 18.1 ActDashAttack（冲刺 — 冷却10s）

```gdscript
## 蓄力 → 快速冲刺 → 刹车减速 → 结束
class_name ActDashAttack extends ActionLeaf

enum Step { FACE_TARGET, CHARGE, DASH, BRAKE, DONE }
var _step: int = Step.FACE_TARGET
var _charge_end: float = 0.0
var _dash_dir: float = 1.0
var _dash_start_x: float = 0.0
var _dash_distance: float = 600.0
var _hit_player: bool = false

func before_run(actor: Node, _bb: Blackboard) -> void:
    _step = Step.FACE_TARGET
    _hit_player = false

func tick(actor: Node, blackboard: Blackboard) -> int:
    var boss := actor as BossGhostWitch
    if boss == null: return FAILURE

    match _step:
        Step.FACE_TARGET:
            var player := boss.get_priority_attack_target()
            if player == null: return FAILURE
            boss.face_toward(player)
            _dash_dir = signf(player.global_position.x - actor.global_position.x)
            if _dash_dir == 0.0: _dash_dir = 1.0
            _step = Step.CHARGE
            _charge_end = Time.get_ticks_msec() + boss.p3_dash_charge_time * 1000.0
            boss.anim_play(&"phase3/dash_charge", false)
            return RUNNING

        Step.CHARGE:
            if Time.get_ticks_msec() >= _charge_end:
                _dash_start_x = actor.global_position.x
                _step = Step.DASH
                boss.anim_play(&"phase3/dash", true)
            return RUNNING

        Step.DASH:
            actor.velocity.x = _dash_dir * boss.p3_dash_speed
            actor.velocity.y = 0.0
            if not _hit_player:
                for body in boss._scythe_detect_area.get_overlapping_bodies():
                    if body.is_in_group("player") and body.has_method("apply_damage"):
                        body.call("apply_damage", 1, actor.global_position)
                        _hit_player = true
                        break
            var traveled := abs(actor.global_position.x - _dash_start_x)
            if traveled >= _dash_distance or actor.is_on_wall():
                actor.velocity.x = 0.0
                _step = Step.BRAKE
                boss.anim_play(&"phase3/dash_brake", false)
            return RUNNING

        Step.BRAKE:
            actor.velocity.x = 0.0
            if boss.anim_is_finished(&"phase3/dash_brake"):
                _set_cooldown(actor, blackboard, "cd_dash", boss.p3_dash_cooldown)
                return SUCCESS
            return RUNNING
    return FAILURE

func _set_cooldown(actor: Node, bb: Blackboard, key: String, cd: float) -> void:
    bb.set_value(key, Time.get_ticks_msec() + cd * 1000.0, str(actor.get_instance_id()))

func interrupt(actor: Node, blackboard: Blackboard) -> void:
    actor.velocity.x = 0.0
    _step = Step.FACE_TARGET
    super(actor, blackboard)
```

### 18.2 ActKick（近身踢人 — 冷却1s）

```gdscript
## 踢人，判定绑定 leg 骨骼。踢中弹飞 300px + HP-1
class_name ActKick extends ActionLeaf

enum Step { PLAY, WAIT, DONE }
var _step: int = Step.PLAY

func before_run(actor: Node, _bb: Blackboard) -> void:
    _step = Step.PLAY

func tick(actor: Node, blackboard: Blackboard) -> int:
    var boss := actor as BossGhostWitch
    if boss == null: return FAILURE

    match _step:
        Step.PLAY:
            var player := boss.get_priority_attack_target()
            if player: boss.face_toward(player)
            boss.anim_play(&"phase3/kick", false)
            _step = Step.WAIT
            return RUNNING
        Step.WAIT:
            if boss.anim_is_finished(&"phase3/kick"):
                _set_cooldown(actor, blackboard, "cd_kick", boss.p3_kick_cooldown)
                return SUCCESS
            return RUNNING
    return FAILURE

func _set_cooldown(actor: Node, bb: Blackboard, key: String, cd: float) -> void:
    bb.set_value(key, Time.get_ticks_msec() + cd * 1000.0, str(actor.get_instance_id()))

func interrupt(actor: Node, blackboard: Blackboard) -> void:
    _step = Step.PLAY
    super(actor, blackboard)
```

### 18.3 ActComboSlash（三连斩 — 冷却1s）

```gdscript
## 3秒内连续检测 attack1/attack2/attack3 区域
class_name ActComboSlash extends ActionLeaf

enum Step { COMBO1, WAIT1, COMBO2, WAIT2, COMBO3, WAIT3, DONE }
var _step: int = Step.COMBO1

func before_run(actor: Node, _bb: Blackboard) -> void:
    _step = Step.COMBO1

func tick(actor: Node, blackboard: Blackboard) -> int:
    var boss := actor as BossGhostWitch
    if boss == null: return FAILURE

    match _step:
        Step.COMBO1:
            var player := boss.get_priority_attack_target()
            if player: boss.face_toward(player)
            boss.anim_play(&"phase3/combo1", false)
            _step = Step.WAIT1
            return RUNNING
        Step.WAIT1:
            if boss.anim_is_finished(&"phase3/combo1"):
                _step = Step.COMBO2
            return RUNNING
        Step.COMBO2:
            boss.anim_play(&"phase3/combo2", false)
            _step = Step.WAIT2
            return RUNNING
        Step.WAIT2:
            if boss.anim_is_finished(&"phase3/combo2"):
                _step = Step.COMBO3
            return RUNNING
        Step.COMBO3:
            boss.anim_play(&"phase3/combo3", false)
            _step = Step.WAIT3
            return RUNNING
        Step.WAIT3:
            if boss.anim_is_finished(&"phase3/combo3"):
                _set_cooldown(actor, blackboard, "cd_combo", boss.p3_combo_cooldown)
                return SUCCESS
            return RUNNING
    return FAILURE

func _set_cooldown(actor: Node, bb: Blackboard, key: String, cd: float) -> void:
    bb.set_value(key, Time.get_ticks_msec() + cd * 1000.0, str(actor.get_instance_id()))

func interrupt(actor: Node, blackboard: Blackboard) -> void:
    _step = Step.COMBO1
    var boss := actor as BossGhostWitch
    if boss: boss._close_all_combo_hitboxes()
    super(actor, blackboard)
```

### 18.4 ActThrowScythe（扔镰刀 — 兜底技能）

```gdscript
## 扔出镰刀 → 本体站桩等待 → 被打则镰刀回航 → 接住 → 结束
class_name ActThrowScythe extends ActionLeaf

enum Step { THROW_ANIM, SCYTHE_OUT, RECALL_WAIT, CATCH, DONE }
var _step: int = Step.THROW_ANIM

func before_run(actor: Node, _bb: Blackboard) -> void:
    _step = Step.THROW_ANIM

func tick(actor: Node, blackboard: Blackboard) -> int:
    var boss := actor as BossGhostWitch
    if boss == null: return FAILURE

    match _step:
        Step.THROW_ANIM:
            var player := boss.get_priority_attack_target()
            if player: boss.face_toward(player)
            boss.anim_play(&"phase3/throw_scythe", false)
            _step = Step.SCYTHE_OUT
            return RUNNING

        Step.SCYTHE_OUT:
            if boss._scythe_instance == null and boss.anim_is_finished(&"phase3/throw_scythe"):
                _spawn_scythe(boss)
            elif boss._scythe_instance == null:
                return RUNNING

            # 镰刀在外，本体原地待机
            boss.anim_play(&"phase3/idle_no_scythe", true)
            boss.velocity.x = 0.0

            if boss._scythe_recall_requested:
                boss._scythe_recall_requested = false
                _recall_scythe(boss)
                _step = Step.RECALL_WAIT
            elif boss._scythe_instance == null or not is_instance_valid(boss._scythe_instance):
                boss._scythe_in_hand = true
                boss.anim_play(&"phase3/catch_scythe", false)
                _step = Step.CATCH
            return RUNNING

        Step.RECALL_WAIT:
            boss.anim_play(&"phase3/idle_no_scythe", true)
            boss.velocity.x = 0.0
            if boss._scythe_instance == null or not is_instance_valid(boss._scythe_instance):
                boss._scythe_in_hand = true
                boss.anim_play(&"phase3/catch_scythe", false)
                _step = Step.CATCH
            return RUNNING

        Step.CATCH:
            if boss.anim_is_finished(&"phase3/catch_scythe"):
                return SUCCESS
            return RUNNING
    return FAILURE

func _spawn_scythe(boss: BossGhostWitch) -> void:
    var scythe: Node2D = boss._witch_scythe_scene.instantiate()
    scythe.add_to_group("witch_scythe")
    var player := boss.get_priority_attack_target()
    if scythe.has_method("setup"):
        scythe.call("setup", player, boss,
            boss.p3_scythe_track_interval,
            boss.p3_scythe_track_count,
            boss.p3_scythe_fly_speed,
            boss.p3_scythe_return_speed)
    scythe.global_position = boss.global_position
    boss.get_parent().add_child(scythe)
    boss._scythe_instance = scythe
    boss._scythe_in_hand = false

func _recall_scythe(boss: BossGhostWitch) -> void:
    if boss._scythe_instance != null and is_instance_valid(boss._scythe_instance):
        if boss._scythe_instance.has_method("recall"):
            boss._scythe_instance.call("recall", boss.global_position)

func interrupt(actor: Node, blackboard: Blackboard) -> void:
    _step = Step.THROW_ANIM
    super(actor, blackboard)
```

### 18.5 ActCastImprison（禁锢 — 地狱之手）

```gdscript
## 在玩家位置召唤地狱之手 → 0.5s 逃跑窗口 → 未逃则僵直3秒
class_name ActCastImprison extends ActionLeaf

enum Step { CAST_ANIM, WAIT_CAST, MONITOR, DONE }
var _step: int = Step.CAST_ANIM

func before_run(actor: Node, _bb: Blackboard) -> void:
    _step = Step.CAST_ANIM

func tick(actor: Node, blackboard: Blackboard) -> int:
    var boss := actor as BossGhostWitch
    if boss == null: return FAILURE

    match _step:
        Step.CAST_ANIM:
            boss.anim_play(&"phase3/imprison", false)
            _step = Step.WAIT_CAST
            return RUNNING
        Step.WAIT_CAST:
            if boss.anim_is_finished(&"phase3/imprison"):
                _spawn_hell_hand(boss)
                _step = Step.MONITOR
            return RUNNING
        Step.MONITOR:
            if boss._hell_hand_instance == null or not is_instance_valid(boss._hell_hand_instance):
                _set_cooldown(actor, blackboard, "cd_imprison", boss.p3_imprison_cooldown)
                return SUCCESS
            return RUNNING
    return FAILURE

func _spawn_hell_hand(boss: BossGhostWitch) -> void:
    var player := boss.get_priority_attack_target()
    if player == null: return
    var hand: Node2D = boss._hell_hand_scene.instantiate()
    hand.add_to_group("hell_hand")
    if hand.has_method("setup"):
        hand.call("setup", player, boss, boss.p3_imprison_escape_time, boss.p3_imprison_stun_time)
    hand.global_position = player.global_position
    boss.get_parent().add_child(hand)
    boss._hell_hand_instance = hand

func _set_cooldown(actor: Node, bb: Blackboard, key: String, cd: float) -> void:
    bb.set_value(key, Time.get_ticks_msec() + cd * 1000.0, str(actor.get_instance_id()))

func interrupt(actor: Node, blackboard: Blackboard) -> void:
    _step = Step.CAST_ANIM
    super(actor, blackboard)
```

### 18.6 ActRunSlash（奔跑斩击 — 禁锢反应）

```gdscript
## 检测到玩家被禁锢 → 跑到玩家位置 → 穿过 200px → 经过时斩击
class_name ActRunSlash extends ActionLeaf

enum Step { RUN_TO, SLASH_THROUGH, DONE }
var _step: int = Step.RUN_TO
var _target_x: float = 0.0
var _overshoot_x: float = 0.0
var _run_dir: float = 1.0
var _slashed: bool = false

func before_run(actor: Node, _bb: Blackboard) -> void:
    _step = Step.RUN_TO
    _slashed = false

func tick(actor: Node, _bb: Blackboard) -> int:
    var boss := actor as BossGhostWitch
    if boss == null: return FAILURE

    match _step:
        Step.RUN_TO:
            var player := boss.get_priority_attack_target()
            if player == null: return FAILURE
            _target_x = player.global_position.x
            _run_dir = signf(_target_x - actor.global_position.x)
            if _run_dir == 0.0: _run_dir = 1.0
            _overshoot_x = _target_x + _run_dir * boss.p3_run_slash_overshoot_px
            boss.face_toward(player)
            boss.anim_play(&"phase3/run_slash", true)
            _step = Step.SLASH_THROUGH
            return RUNNING

        Step.SLASH_THROUGH:
            actor.velocity.x = _run_dir * boss.p3_run_speed
            if not _slashed:
                var player := boss.get_priority_attack_target()
                if player != null:
                    var passed := (_run_dir > 0 and actor.global_position.x >= _target_x) \
                                or (_run_dir < 0 and actor.global_position.x <= _target_x)
                    if passed:
                        if player.has_method("apply_damage"):
                            player.call("apply_damage", 1, actor.global_position)
                        _slashed = true
                        boss._player_imprisoned = false
                        if boss._hell_hand_instance and is_instance_valid(boss._hell_hand_instance):
                            boss._hell_hand_instance.queue_free()
            var reached := (_run_dir > 0 and actor.global_position.x >= _overshoot_x) \
                          or (_run_dir < 0 and actor.global_position.x <= _overshoot_x)
            if reached or actor.is_on_wall():
                actor.velocity.x = 0.0
                boss.anim_play(&"phase3/idle", true)
                return SUCCESS
            return RUNNING
    return FAILURE

func interrupt(actor: Node, blackboard: Blackboard) -> void:
    actor.velocity.x = 0.0
    _step = Step.RUN_TO
    super(actor, blackboard)
```

### 18.7 ActThrowScytheUpward（向上扔追踪镰刀 — 禁锢反应：玩家在上方）

```gdscript
## 跑到玩家 X 位置 → 向上扔镰刀 → 1秒内追踪到玩家位置
class_name ActThrowScytheUpward extends ActionLeaf

enum Step { RUN_TO_X, THROW_UP, WAIT_SCYTHE, DONE }
var _step: int = Step.RUN_TO_X

func before_run(actor: Node, _bb: Blackboard) -> void:
    _step = Step.RUN_TO_X

func tick(actor: Node, _bb: Blackboard) -> int:
    var boss := actor as BossGhostWitch
    if boss == null: return FAILURE

    match _step:
        Step.RUN_TO_X:
            var player := boss.get_priority_attack_target()
            if player == null: return FAILURE
            var h_dist := abs(actor.global_position.x - player.global_position.x)
            if h_dist < 30.0:
                actor.velocity.x = 0.0
                _step = Step.THROW_UP
            else:
                var dir := signf(player.global_position.x - actor.global_position.x)
                actor.velocity.x = dir * boss.p3_run_speed
                boss.anim_play(&"phase3/walk", true)
            return RUNNING

        Step.THROW_UP:
            actor.velocity.x = 0.0
            boss.anim_play(&"phase3/throw_scythe", false)
            if boss.anim_is_finished(&"phase3/throw_scythe"):
                _spawn_tracking_scythe(boss)
                _step = Step.WAIT_SCYTHE
            return RUNNING

        Step.WAIT_SCYTHE:
            boss.anim_play(&"phase3/idle_no_scythe", true)
            if boss._scythe_instance == null or not is_instance_valid(boss._scythe_instance):
                boss._scythe_in_hand = true
                boss.anim_play(&"phase3/catch_scythe", false)
                boss._player_imprisoned = false
                if boss._hell_hand_instance and is_instance_valid(boss._hell_hand_instance):
                    boss._hell_hand_instance.queue_free()
                return SUCCESS
            return RUNNING
    return FAILURE

func _spawn_tracking_scythe(boss: BossGhostWitch) -> void:
    var scythe: Node2D = boss._witch_scythe_scene.instantiate()
    scythe.add_to_group("witch_scythe")
    var player := boss.get_priority_attack_target()
    if scythe.has_method("setup_tracking"):
        scythe.call("setup_tracking", player, boss, boss.p3_scythe_fly_speed)
    scythe.global_position = boss.global_position + Vector2(0, -50)
    boss.get_parent().add_child(scythe)
    boss._scythe_instance = scythe
    boss._scythe_in_hand = false

func interrupt(actor: Node, blackboard: Blackboard) -> void:
    actor.velocity.x = 0.0
    _step = Step.RUN_TO_X
    super(actor, blackboard)
```

### 18.8 ActSummonGhosts（召唤幽灵 — 施法含 combo3 攻击）

```gdscript
## 施法起手（含 combo3 攻击判定）→ 生成幽灵波次 → summon_loop 维持 → 等所有 GhostSummon 销毁 → 结束
## 全程不可移动
class_name ActSummonGhosts extends ActionLeaf

enum Step { CAST, SUMMON_LOOP, DONE }
var _step: int = Step.CAST
var _wave_index: int = 0
var _wave_timer: float = 0.0
var _wave_interval: float = 0.0
var _cast_done: bool = false

func before_run(actor: Node, _bb: Blackboard) -> void:
    _step = Step.CAST
    _wave_index = 0
    _wave_timer = 0.0
    _cast_done = false

func tick(actor: Node, blackboard: Blackboard) -> int:
    var boss := actor as BossGhostWitch
    if boss == null: return FAILURE
    var dt := get_physics_process_delta_time()
    actor.velocity.x = 0.0  # 全程锁定移动

    match _step:
        Step.CAST:
            if not _cast_done:
                boss.anim_play(&"phase3/summon", false)
                _wave_interval = 5.0 / float(boss.p3_summon_wave_count)

            _wave_timer += dt
            var expected_waves := int(_wave_timer / _wave_interval)
            if expected_waves > _wave_index and _wave_index < boss.p3_summon_wave_count:
                _spawn_wave(boss)
                _wave_index += 1

            if boss.anim_is_finished(&"phase3/summon"):
                _cast_done = true
                _step = Step.SUMMON_LOOP
            return RUNNING

        Step.SUMMON_LOOP:
            boss.anim_play(&"phase3/summon_loop", true)
            if _wave_index < boss.p3_summon_wave_count:
                _wave_timer += dt
                var expected_waves := int(_wave_timer / _wave_interval)
                if expected_waves > _wave_index:
                    _spawn_wave(boss)
                    _wave_index += 1

            var remaining: Array[Node] = actor.get_tree().get_nodes_in_group("ghost_summon")
            if remaining.is_empty() and _wave_index >= boss.p3_summon_wave_count:
                boss.anim_play(&"phase3/idle", true)
                _set_cooldown(actor, blackboard, "cd_summon", boss.p3_summon_cooldown)
                return SUCCESS
            return RUNNING
    return FAILURE

func _spawn_wave(boss: BossGhostWitch) -> void:
    var player := boss.get_priority_attack_target()
    if player == null: return
    var positions: Array[Vector2] = []
    positions.append(player.global_position)
    for i in range(boss.p3_summon_circle_count - 1):
        var random_x := player.global_position.x + randf_range(-300, 300)
        positions.append(Vector2(random_x, player.global_position.y))
    for pos in positions:
        var summon: Node2D = boss._ghost_summon_scene.instantiate()
        summon.add_to_group("ghost_summon")
        if summon.has_method("setup"):
            summon.call("setup", 0.3)
        summon.global_position = pos
        boss.get_parent().add_child(summon)

func _set_cooldown(actor: Node, bb: Blackboard, key: String, cd: float) -> void:
    bb.set_value(key, Time.get_ticks_msec() + cd * 1000.0, str(actor.get_instance_id()))

func interrupt(actor: Node, blackboard: Blackboard) -> void:
    _step = Step.CAST
    _cast_done = false
    var boss := actor as BossGhostWitch
    if boss: boss._close_all_combo_hitboxes()
    super(actor, blackboard)
```

### 18.9 ActP3MoveTowardPlayer（Phase 3 移动）

```gdscript
class_name ActP3MoveTowardPlayer extends ActionLeaf

func tick(actor: Node, _bb: Blackboard) -> int:
    var boss := actor as BossGhostWitch
    if boss == null: return FAILURE
    if not boss._scythe_in_hand:
        actor.velocity.x = 0.0
        boss.anim_play(&"phase3/idle_no_scythe", true)
        return RUNNING
    var player := boss.get_priority_attack_target()
    if player == null:
        actor.velocity.x = 0.0
        boss.anim_play(&"phase3/idle", true)
        return RUNNING
    var h_dist := abs(player.global_position.x - actor.global_position.x)
    if h_dist < 30.0:
        actor.velocity.x = 0.0
        boss.anim_play(&"phase3/idle", true)
    else:
        var dir := signf(player.global_position.x - actor.global_position.x)
        actor.velocity.x = dir * boss.p3_move_speed
        boss.face_toward(player)
        boss.anim_play(&"phase3/walk", true)
    return RUNNING
```

### 18.10 ActP3IdleNoScythe（无镰刀待机兜底）

```gdscript
## 镰刀不在手时的兜底：原地待机，等待镰刀回航
class_name ActP3IdleNoScythe extends ActionLeaf

func tick(actor: Node, _bb: Blackboard) -> int:
    var boss := actor as BossGhostWitch
    if boss == null: return FAILURE
    actor.velocity.x = 0.0
    boss.anim_play(&"phase3/idle_no_scythe", true)
    return RUNNING
```

---

## 17. Phase 3 子实例场景设计

### 17.1 WitchScythe.tscn（镰刀实例）

**节点结构：**
```
WitchScythe (Node2D)  # witch_scythe.gd
├── SpineSprite        # 镰刀飞行动画
└── HitArea (Area2D)   # 全程碰到玩家即伤害
    └── CollisionShape2D  # 默认 enabled（扔出即生效）
```

> 不需要 AttackArea（没有砍击动作）。HitArea 全程开启，碰到就伤害。

**动画清单：**

| 动画名 | loop | 用途 |
|---|---|---|
| `fly` | true | 镰刀飞行旋转（扔出后全程播放）|
| `return_end` | false | 回航到达 Boss 身边后的结束过渡 |

**witch_scythe.gd 核心逻辑：**

```gdscript
extends Node2D

## 镰刀实例：fly 动画循环飞行，每次检测玩家位置并转向飞过去，
## 检测次数用完后直线回航，到达后播 return_end，播完通知 Boss。
## 全程碰到玩家就伤害。

enum ScytheState { FLYING, RETURNING, RETURN_END }

var _state: int = ScytheState.FLYING
var _player: Node2D = null
var _boss: Node2D = null
var _track_interval: float = 1.0
var _track_count_max: int = 3
var _track_count: int = 0
var _fly_speed: float = 300.0
var _return_speed: float = 500.0
var _target_pos: Vector2 = Vector2.ZERO
var _track_timer: float = 0.0
var _hit_player_this_frame: bool = false

func setup(player: Node2D, boss: Node2D, track_interval: float,
           track_count: int, fly_speed: float, return_speed: float) -> void:
    _player = player
    _boss = boss
    _track_interval = track_interval
    _track_count_max = track_count
    _fly_speed = fly_speed
    _return_speed = return_speed
    _track_count = 0
    _track_timer = 0.0
    _state = ScytheState.FLYING
    _update_target()

func setup_tracking(player: Node2D, boss: Node2D, fly_speed: float) -> void:
    _player = player
    _boss = boss
    _track_interval = 0.0
    _track_count_max = 1
    _fly_speed = fly_speed
    _return_speed = fly_speed * 1.5
    _track_count = 0
    _state = ScytheState.FLYING
    _update_target()

func _ready() -> void:
    _play_anim(&"fly", true)
    $HitArea.body_entered.connect(_on_body_entered)

func _physics_process(dt: float) -> void:
    _hit_player_this_frame = false
    match _state:
        ScytheState.FLYING: _tick_flying(dt)
        ScytheState.RETURNING: _tick_returning(dt)
        ScytheState.RETURN_END: _tick_return_end()

func _tick_flying(dt: float) -> void:
    var dir := (_target_pos - global_position).normalized()
    global_position += dir * _fly_speed * dt
    if global_position.distance_to(_target_pos) < 20.0:
        _track_count += 1
        if _track_count >= _track_count_max:
            _state = ScytheState.RETURNING
        else:
            _track_timer = 0.0
            _update_target()
    _track_timer += dt
    if _track_timer >= _track_interval and _track_count < _track_count_max:
        _track_timer = 0.0
        _update_target()

func _tick_returning(dt: float) -> void:
    if _boss == null or not is_instance_valid(_boss):
        queue_free()
        return
    var boss_pos := _boss.global_position
    var dir := (boss_pos - global_position).normalized()
    global_position += dir * _return_speed * dt
    if global_position.distance_to(boss_pos) < 30.0:
        _play_anim(&"return_end", false)
        _state = ScytheState.RETURN_END

func _tick_return_end() -> void:
    if _is_anim_finished(&"return_end"):
        if _boss and is_instance_valid(_boss):
            _boss._scythe_in_hand = true
            _boss._scythe_instance = null
        queue_free()

func recall(_target_pos: Vector2) -> void:
    _state = ScytheState.RETURNING

func _update_target() -> void:
    if _player and is_instance_valid(_player):
        _target_pos = _player.global_position

func _on_body_entered(body: Node2D) -> void:
    if _hit_player_this_frame: return
    if body.is_in_group("player") and body.has_method("apply_damage"):
        body.call("apply_damage", 1, global_position)
        _hit_player_this_frame = true

func _play_anim(_name: StringName, _loop: bool) -> void:
    pass  # 实际走 AnimDriverSpine
func _is_anim_finished(_name: StringName) -> bool:
    return false
```

### 17.2 HellHand.tscn（地狱之手）

**节点结构：**
```
HellHand (Node2D)  # hell_hand.gd
├── SpineSprite     # 地狱之手 Spine 动画
├── CaptureArea (Area2D)  # 捕捉检测区（绑定 Spine 骨骼）
│   └── CollisionShape2D
└── HitArea (Area2D)       # 被 ghostfist 打碎
    └── CollisionShape2D
```

**动画清单：**

| 动画名 | loop | 事件 | 用途 |
|---|---|---|---|
| `appear` | false | `capture_check`（检测帧） | 地狱之手从地面出现 |
| `hold` | true | — | 抓住玩家，持续禁锢 |
| `close` | false | — | 没抓到 或 被打断 或 禁锢结束后的收回消失 |

**事件驱动逻辑：不用 timer，用 Spine 事件 `capture_check` 决定是否抓住玩家。**

**hell_hand.gd 核心逻辑：**

```gdscript
extends Node2D

enum HandState { APPEAR, HOLD, CLOSING }

var _state: int = HandState.APPEAR
var _player: Node2D = null
var _boss: Node2D = null
var _stun_time: float = 3.0
var _imprison_end: float = 0.0
var _player_captured: bool = false

func setup(player: Node2D, boss: Node2D, escape_time: float, stun_time: float) -> void:
    _player = player
    _boss = boss
    _stun_time = stun_time
    # escape_time 不再用 timer，由动画事件 capture_check 的时机决定

func _ready() -> void:
    _state = HandState.APPEAR
    _play_anim(&"appear", false)

    # 连接 Spine 事件
    var spine: Node = get_node_or_null("SpineSprite")
    if spine and spine.has_signal("animation_event"):
        spine.animation_event.connect(_on_spine_event)

    # ghostfist 击碎检测
    $HitArea.area_entered.connect(_on_ghostfist_hit)

func _on_spine_event(a1, a2, a3, a4) -> void:
    var event_name := _extract_event_name(a1, a2, a3, a4)
    match event_name:
        &"capture_check":
            # 动画中的检测帧：玩家还在 CaptureArea 内？
            if _is_player_in_capture_area():
                _capture_player()
            else:
                # 没抓到 → 播放收回动画消失
                _state = HandState.CLOSING
                _play_anim(&"close", false)

func _physics_process(_dt: float) -> void:
    match _state:
        HandState.APPEAR:
            # 等待 Spine 事件 capture_check 触发
            if _is_anim_finished(&"appear") and not _player_captured:
                # appear 动画播完但 capture_check 还没触发（防御性兜底）
                _state = HandState.CLOSING
                _play_anim(&"close", false)
        HandState.HOLD:
            if Time.get_ticks_msec() >= _imprison_end:
                _release_player()
                _state = HandState.CLOSING
                _play_anim(&"close", false)
        HandState.CLOSING:
            if _is_anim_finished(&"close"):
                _cleanup_and_free()

func _is_player_in_capture_area() -> bool:
    for body in $CaptureArea.get_overlapping_bodies():
        if body.is_in_group("player"): return true
    return false

func _capture_player() -> void:
    _player_captured = true
    _state = HandState.HOLD
    _imprison_end = Time.get_ticks_msec() + _stun_time * 1000.0
    _play_anim(&"hold", true)
    if _player and is_instance_valid(_player):
        if _player.has_method("set_external_control_frozen"):
            _player.call("set_external_control_frozen", true)
    if _boss and is_instance_valid(_boss):
        _boss._player_imprisoned = true

func _release_player() -> void:
    _player_captured = false
    if _player and is_instance_valid(_player):
        if _player.has_method("set_external_control_frozen"):
            _player.call("set_external_control_frozen", false)
    if _boss and is_instance_valid(_boss):
        _boss._player_imprisoned = false

func _on_ghostfist_hit(area: Area2D) -> void:
    if area.is_in_group("ghost_fist_hitbox"):
        _release_player()
        _state = HandState.CLOSING
        _play_anim(&"close", false)

func _cleanup_and_free() -> void:
    _release_player()
    queue_free()

func _exit_tree() -> void:
    _release_player()

func _extract_event_name(a1, a2, a3, a4) -> StringName:
    for a in [a1, a2, a3, a4]:
        if a is Object and a.has_method("get_data"):
            var data = a.get_data()
            if data != null and data.has_method("get_event_name"):
                return StringName(data.get_event_name())
    return &""

func _play_anim(_name: StringName, _loop: bool) -> void:
    pass  # 实际走 AnimDriverSpine
func _is_anim_finished(_name: StringName) -> bool:
    return false
```

### 17.3 GhostSummon.tscn（召唤幽灵 — 圆圈飞出）

**节点结构：**
```
GhostSummon (Node2D)  # ghost_summon.gd
├── SpineSprite       # 圆圈 + 飞出幽灵动画（ghost 骨骼）
└── GhostHitArea (Area2D)  # 伤害检测盒，绑定 ghost 骨骼
    └── CollisionShape2D    # 默认 disabled
```

> HitArea 绑定在 Spine 的 `ghost` 骨骼上，每帧跟随骨骼位置。
> 伤害检测由 Spine 事件控制开关，不是 timer。

**动画清单：**

| 动画名 | loop | 事件 | 用途 |
|---|---|---|---|
| `circle_appear` | false | — | 地面圆圈出现 |
| `ghost_fly_out` | false | `ghost_hitbox_on`、`ghost_hitbox_off` | 亡灵从圆圈中往上飞出 |

**ghost_summon.gd 核心逻辑：**

```gdscript
extends Node2D

var _delay: float = 0.3
var _spawned: bool = false
var _lifetime: float = 3.0
var _ghost_hit_area: Area2D = null

func setup(delay: float) -> void:
    _delay = delay

func _ready() -> void:
    _ghost_hit_area = $GhostHitArea
    _play_anim(&"circle_appear", false)
    _set_hitarea_enabled(false)

    # 连接 Spine 事件
    var spine: Node = get_node_or_null("SpineSprite")
    if spine and spine.has_signal("animation_event"):
        spine.animation_event.connect(_on_spine_event)

    # 碰撞伤害
    _ghost_hit_area.body_entered.connect(_on_body_entered)

func _physics_process(dt: float) -> void:
    if not _spawned:
        _delay -= dt
        if _delay <= 0.0:
            _spawned = true
            _play_anim(&"ghost_fly_out", false)
            # hitbox 由 Spine 事件 ghost_hitbox_on 控制，不在这里开
    else:
        _lifetime -= dt
        if _lifetime <= 0.0:
            queue_free()

    # 每帧同步 GhostHitArea 到 ghost 骨骼位置
    _sync_hitarea_to_bone()

func _on_spine_event(a1, a2, a3, a4) -> void:
    var event_name := _extract_event_name(a1, a2, a3, a4)
    match event_name:
        &"ghost_hitbox_on":
            _set_hitarea_enabled(true)
        &"ghost_hitbox_off":
            _set_hitarea_enabled(false)

func _sync_hitarea_to_bone() -> void:
    if _ghost_hit_area == null: return
    var spine: Node = get_node_or_null("SpineSprite")
    if spine == null: return
    # 通过 AnimDriverSpine 或直接 SpineSprite 获取骨骼位置
    if spine.has_method("get_skeleton"):
        var skeleton = spine.get_skeleton()
        if skeleton and skeleton.has_method("find_bone"):
            var bone = skeleton.find_bone("ghost")
            if bone:
                # 使用骨骼世界坐标
                var bone_pos := Vector2.ZERO
                if bone.has_method("get_world_position_x") and bone.has_method("get_world_position_y"):
                    bone_pos = Vector2(bone.get_world_position_x(), bone.get_world_position_y())
                    _ghost_hit_area.position = bone_pos

func _on_body_entered(body: Node2D) -> void:
    if body.is_in_group("player") and body.has_method("apply_damage"):
        body.call("apply_damage", 1, global_position)

func _set_hitarea_enabled(enabled: bool) -> void:
    _ghost_hit_area.set_deferred("monitoring", enabled)
    for child in _ghost_hit_area.get_children():
        if child is CollisionShape2D:
            child.set_deferred("disabled", not enabled)

func _extract_event_name(a1, a2, a3, a4) -> StringName:
    for a in [a1, a2, a3, a4]:
        if a is Object and a.has_method("get_data"):
            var data = a.get_data()
            if data != null and data.has_method("get_event_name"):
                return StringName(data.get_event_name())
    return &""

func _play_anim(_name: StringName, _loop: bool) -> void:
    pass  # 实际走 SpineSprite
```
---

## 18. Phase 3 死亡流程

```
hp <= 0 时：
1. hp_locked = true
2. 中断所有攻击流
3. 清理场景中所有 Boss 子实例：
   → call_group("witch_scythe", "queue_free")
   → call_group("hell_hand", "queue_free")
   → call_group("ghost_summon", "queue_free")
   → 以及 Phase 2 残留（ghost_bomb, ghost_wraith, ghost_elite, ghost_tug）
4. Boss 播放 phase3/death
5. Spine 事件 "death_finished" 后切到 phase3/death_loop
6. death_loop 持续播放
```

```gdscript
func _begin_death() -> void:
    hp_locked = true
    _phase_transitioning = true
    velocity = Vector2.ZERO
    _cleanup_all_instances()
    anim_play(&"phase3/death", false)

func _on_anim_completed(_track: int, anim_name: StringName) -> void:
    if anim_name == _current_anim:
        _current_anim_finished = true
    if anim_name == &"phase3/death":
        anim_play(&"phase3/death_loop", true)

func _cleanup_all_instances() -> void:
    for group_name in ["ghost_bomb", "ghost_wraith", "ghost_elite", "ghost_tug",
                       "witch_scythe", "hell_hand", "ghost_summon"]:
        get_tree().call_group(group_name, "queue_free")
```

---

