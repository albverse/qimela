# 《幽灵魔女 BossGhostWitch》工程蓝图 — B. Phase 1 & Phase 2 设计

> 本文档是三部曲的第二部，包含 Phase 1（石像形态）和 Phase 2（祈祷形态）的全部行为树、ActionLeaf、子实例、阶段过渡。
> **前置依赖：必须先读 A. 全局概览。**

---

## 7. 行为树结构

### 7.1 Phase 1 行为树

```
BeehaveTree
└── SelectorReactiveComposite [RootSelector]
    │
    ├── SequenceReactiveComposite [PhaseTransitionSeq]
    │   ├── CondPhaseTransitioning        ← hp_locked / 变身中 → SUCCESS
    │   └── ActWaitTransition             ← RUNNING 直到变身完毕
    │
    ├── SequenceReactiveComposite [Phase1Seq]
    │   ├── CondIsPhase (phase=1)
    │   └── SelectorReactiveComposite [P1Selector]
    │       │
    │       ├── SequenceReactiveComposite [P1StartBattleSeq]
    │       │   ├── CondBattleNotStarted
    │       │   └── ActStartBattle         ← 开场动画流程
    │       │
    │       ├── SequenceReactiveComposite [P1ThrowBabySeq]
    │       │   ├── CondBabyInHug
    │       │   ├── CondPlayerInRange (range=500)
    │       │   └── ActThrowBaby           ← 投掷婴儿石像
    │       │
    │       ├── SequenceReactiveComposite [P1BabyAttackFlowSeq]
    │       │   ├── CondBabyNotInHug
    │       │   └── ActBabyAttackFlow      ← 婴儿爆炸→修复→检测→冲刺→等待→冲回→收招→返航
    │       │
    │       └── ActSlowMoveToPlayer        ← 兜底：玩家不在攻击范围内 → 缓慢向玩家移动
    │
    ├── SequenceReactiveComposite [Phase2Seq]
    │   ├── CondIsPhase (phase=2)
    │   └── SelectorReactiveComposite [P2Selector]
    │       │  (见 7.2)
    │       └── ...
    │
    └── SequenceReactiveComposite [Phase3Seq]
        ├── CondIsPhase (phase=3)
        └── SelectorReactiveComposite [P3Selector]
            │  (见 14.2)
```

### 7.2 Phase 2 行为树

```
SelectorReactiveComposite [P2Selector]
│
├── SequenceComposite [P2ScytheSlashSeq]             ← 优先级 1（最高）
│   ├── CondPlayerInRange (range=100)
│   ├── CondCooldownReady (key="cd_scythe", cooldown=scythe_slash_cooldown)
│   └── ActScytheSlash
│
├── SequenceComposite [P2TombstoneSeq]               ← 优先级 2
│   ├── CondPlayerInRange (range=500)
│   ├── CondCooldownReady (key="cd_tombstone", cooldown=tombstone_drop_cooldown)
│   └── ActTombstoneDrop
│
├── SequenceComposite [P2UndeadWindSeq]              ← 优先级 3
│   ├── CondPlayerInRange (range=300)
│   ├── InverterDecorator
│   │   └── CondPlayerInRange (range=100)             ← NOT: 100px以内不触发
│   ├── CondCooldownReady (key="cd_wind", cooldown=undead_wind_cooldown)
│   └── ActUndeadWind
│
├── SequenceComposite [P2GhostTugSeq]                ← 优先级 4
│   ├── InverterDecorator
│   │   └── CondPlayerInRange (range=500)             ← NOT: 500px以内不触发
│   ├── CondCooldownReady (key="cd_tug", cooldown=ghost_tug_cooldown)
│   └── ActGhostTug
│
├── SequenceComposite [P2PassiveBombSeq]             ← 被动技能（空闲时）
│   ├── CondGhostBombCanSpawn (max_count=3)
│   ├── CondCooldownReady (key="cd_bomb", cooldown=ghost_bomb_interval)
│   └── ActSpawnGhostBomb
│
└── ActMoveTowardPlayer                               ← 兜底：玩家不在攻击范围内 / 技能冷却中 → 向玩家移动
```

### 7.3 攻击优先级总结（Phase 2 距离范围解析）

```
玩家距离 ≤ 100px   → 镰刀斩（cd=1s）; 冷却中 → 等待
100px < 距离 ≤ 300px → 先检查亡灵气流（cd=15s）; 冷却中 → 飞天砸落
300px < 距离 ≤ 500px → 飞天砸落（cd=3s）; 冷却中 → 缓慢向玩家移动
距离 > 500px       → 幽灵拔河（cd=5s）; 冷却中 → 缓慢向玩家移动
炸弹 CD 就绪且数量未满 → 释放自爆幽灵 / 否则缓慢向玩家移动
任何时候玩家超出全部攻击检测范围 → 缓慢向玩家移动（SelectorReactive 自然落到末位兜底分支）
```

---

---

## 8. 自定义 Condition/Action 叶节点详细设计

### 8.1 通用 ConditionLeaf

#### CondIsPhase

```gdscript
## 检查 Boss 当前是否处于指定阶段
class_name CondIsPhase extends ConditionLeaf

@export var phase: int = 1

func tick(actor: Node, _blackboard: Blackboard) -> int:
    var boss: BossGhostWitch = actor as BossGhostWitch
    if boss == null: return FAILURE
    return SUCCESS if boss.current_phase == phase else FAILURE
```

#### CondPhaseTransitioning

```gdscript
## 检查 Boss 是否正在变身
class_name CondPhaseTransitioning extends ConditionLeaf

func tick(actor: Node, _blackboard: Blackboard) -> int:
    var boss: BossGhostWitch = actor as BossGhostWitch
    if boss == null: return FAILURE
    return SUCCESS if boss._phase_transitioning else FAILURE
```

#### CondPlayerInRange

```gdscript
## 自给自足感知：检测玩家是否在指定范围内
class_name CondPlayerInRange extends ConditionLeaf

@export var range_px: float = 500.0

func tick(actor: Node, blackboard: Blackboard) -> int:
    var boss: BossGhostWitch = actor as BossGhostWitch
    if boss == null: return FAILURE
    var player: Node2D = boss.get_priority_attack_target()
    if player == null: return FAILURE
    # 使用水平距离（2D 横向游戏）
    var h_dist: float = abs(player.global_position.x - actor.global_position.x)
    if h_dist <= range_px:
        var actor_id := str(actor.get_instance_id())
        blackboard.set_value("player", player, actor_id)
        return SUCCESS
    return FAILURE
```

#### CondCooldownReady（自管理冷却模式）

```gdscript
## 检查指定技能是否冷却完毕（blackboard 自管理，不受 interrupt 影响）
class_name CondCooldownReady extends ConditionLeaf

@export var cooldown_key: String = "cd_skill"
@export var cooldown_sec: float = 3.0

func tick(actor: Node, blackboard: Blackboard) -> int:
    var actor_id := str(actor.get_instance_id())
    var end_time: float = blackboard.get_value(cooldown_key, 0.0, actor_id)
    if Time.get_ticks_msec() < end_time:
        return FAILURE
    return SUCCESS
```

#### CondBabyInHug / CondBabyNotInHug

```gdscript
class_name CondBabyInHug extends ConditionLeaf
func tick(actor: Node, _bb: Blackboard) -> int:
    var boss := actor as BossGhostWitch
    return SUCCESS if boss != null and boss.baby_state == BossGhostWitch.BabyState.IN_HUG else FAILURE

class_name CondBabyNotInHug extends ConditionLeaf
func tick(actor: Node, _bb: Blackboard) -> int:
    var boss := actor as BossGhostWitch
    return SUCCESS if boss != null and boss.baby_state != BossGhostWitch.BabyState.IN_HUG else FAILURE
```

#### CondBattleNotStarted

```gdscript
class_name CondBattleNotStarted extends ConditionLeaf
func tick(actor: Node, _bb: Blackboard) -> int:
    var boss := actor as BossGhostWitch
    return SUCCESS if boss != null and not boss._battle_started else FAILURE
```

> `CondAllSkillsOnCooldown` 已从当前实现中移除（历史方案）。
> 现版本的 `GhostBomb` 只依赖：`CondGhostBombCanSpawn + CondCooldownReady(cd_bomb)`。

#### CondGhostBombCanSpawn

```gdscript
class_name CondGhostBombCanSpawn extends ConditionLeaf
@export var max_count: int = 3

func tick(actor: Node, _bb: Blackboard) -> int:
    var bombs: Array[Node] = actor.get_tree().get_nodes_in_group("ghost_bomb")
    return SUCCESS if bombs.size() < max_count else FAILURE
```

---

### 8.2 Phase 1 ActionLeaf

#### ActStartBattle（开场动画流）

```gdscript
## 首次检测到玩家 → start_attack → start_attack_loop(4s) → start_attack_exter → 战斗开始
class_name ActStartBattle extends ActionLeaf

enum Step { PLAY_START, WAIT_START, PLAY_LOOP, WAIT_LOOP, PLAY_EXTER, WAIT_EXTER, DONE }
var _step: int = Step.PLAY_START
var _loop_end_time: float = 0.0

func before_run(actor: Node, _bb: Blackboard) -> void:
    _step = Step.PLAY_START

func tick(actor: Node, blackboard: Blackboard) -> int:
    var boss := actor as BossGhostWitch
    if boss == null: return FAILURE

    match _step:
        Step.PLAY_START:
            boss.anim_play(&"phase1/start_attack", false)
            _step = Step.WAIT_START
            return RUNNING
        Step.WAIT_START:
            if boss.anim_is_finished(&"phase1/start_attack"):
                # 检测玩家是否在镰刀检测区
                if _player_in_scythe_area(boss):
                    _damage_player(boss, 1)
                _step = Step.PLAY_LOOP
            return RUNNING
        Step.PLAY_LOOP:
            boss.anim_play(&"phase1/start_attack_loop", true)
            _loop_end_time = Time.get_ticks_msec() + boss.start_attack_loop_duration * 1000.0
            _step = Step.WAIT_LOOP
            return RUNNING
        Step.WAIT_LOOP:
            if Time.get_ticks_msec() >= _loop_end_time:
                _step = Step.PLAY_EXTER
            return RUNNING
        Step.PLAY_EXTER:
            boss.anim_play(&"phase1/start_attack_exter", false)
            _step = Step.WAIT_EXTER
            return RUNNING
        Step.WAIT_EXTER:
            if boss.anim_is_finished(&"phase1/start_attack_exter"):
                boss._battle_started = true
                return SUCCESS
            return RUNNING
    return FAILURE

func _player_in_scythe_area(boss: BossGhostWitch) -> bool:
    # 通过 ScytheDetectArea.get_overlapping_bodies() 检测玩家
    for body in boss._scythe_detect_area.get_overlapping_bodies():
        if body.is_in_group("player"):
            return true
    return false

func _damage_player(boss: BossGhostWitch, amount: int) -> void:
    for body in boss._scythe_detect_area.get_overlapping_bodies():
        if body.is_in_group("player") and body.has_method("apply_damage"):
            body.call("apply_damage", amount, boss.global_position)

func interrupt(actor: Node, blackboard: Blackboard) -> void:
    _step = Step.PLAY_START
    super(actor, blackboard)
```

#### ActThrowBaby（投掷婴儿石像）

```gdscript
## 播放抛婴儿动画 → 婴儿从 mark2D_hug 发射飞向玩家 → 进入 THROWN 状态
class_name ActThrowBaby extends ActionLeaf

enum Step { ANIM_THROW, WAIT_ANIM, BABY_FLYING, DONE }
var _step: int = Step.ANIM_THROW
var _target_pos: Vector2 = Vector2.ZERO

func before_run(actor: Node, _bb: Blackboard) -> void:
    _step = Step.ANIM_THROW

func tick(actor: Node, blackboard: Blackboard) -> int:
    var boss := actor as BossGhostWitch
    if boss == null: return FAILURE
    var actor_id := str(actor.get_instance_id())
    var player: Node2D = blackboard.get_value("player", null, actor_id)

    match _step:
        Step.ANIM_THROW:
            if player == null: return FAILURE
            _target_pos = player.global_position
            boss.anim_play(&"phase1/throw", false)
            _step = Step.WAIT_ANIM
            return RUNNING
        Step.WAIT_ANIM:
            # 等待 Spine 事件 "baby_release" 触发
            # 事件回调中会设置 boss.baby_state = BabyState.THROWN
            # 并让婴儿 SpineSprite visible，开始飞行
            if boss.baby_state == BossGhostWitch.BabyState.THROWN:
                _step = Step.BABY_FLYING
            return RUNNING
        Step.BABY_FLYING:
            # 婴儿飞行中播放旋转动画
            boss.baby_anim_play(&"baby/spin", true)
            # 飞行移动逻辑在 boss._tick_baby_flight() 中处理
            # 婴儿撞到地面 → 自动进入 EXPLODED
            if boss.baby_state != BossGhostWitch.BabyState.THROWN:
                return SUCCESS
            return RUNNING
    return FAILURE

func interrupt(actor: Node, blackboard: Blackboard) -> void:
    _step = Step.ANIM_THROW
    super(actor, blackboard)
```

#### ActBabyAttackFlow（婴儿攻击流1：爆炸→修复→检测→冲刺→等待→冲回→收招→返航）

```gdscript
## 婴儿石像的完整攻击循环（多帧状态机）
class_name ActBabyAttackFlow extends ActionLeaf

enum Step {
    EXPLODE,           # 爆炸动画 + 开启 realhurtbox
    REPAIR,            # 修复动画（期间核心可被 ghostfist 攻击）
    CHECK_PLAYER,      # 修复完毕 → 检测玩家是否在范围内
    DASH_TO_PLAYER,    # 向玩家方向冲刺（蓄力→dash_go→dash_loop移动）
    POST_DASH_WAIT,    # 冲刺到达后等待 0.7s
    DASH_BACK,         # 向冲刺前位置冲回（直接 dash_loop，跳过蓄力）
    WIND_UP,           # 收招动画
    RETURN_HOME,       # 飞回母体
    DONE
}

var _step: int = Step.EXPLODE
var _dash_origin: Vector2 = Vector2.ZERO
var _dash_target: Vector2 = Vector2.ZERO
var _wait_end: float = 0.0

func before_run(actor: Node, _bb: Blackboard) -> void:
    _step = Step.EXPLODE
    var boss := actor as BossGhostWitch
    if boss: boss._baby_dash_go_triggered = false

func tick(actor: Node, blackboard: Blackboard) -> int:
    var boss := actor as BossGhostWitch
    if boss == null: return FAILURE

    match _step:
        Step.EXPLODE:
            return _tick_explode(boss)
        Step.REPAIR:
            return _tick_repair(boss)
        Step.CHECK_PLAYER:
            return _tick_check_player(boss)
        Step.DASH_TO_PLAYER:
            return _tick_dash(boss, true)
        Step.POST_DASH_WAIT:
            return _tick_wait(boss)
        Step.DASH_BACK:
            return _tick_dash(boss, false)
        Step.WIND_UP:
            return _tick_wind_up(boss)
        Step.RETURN_HOME:
            return _tick_return(boss)
    return FAILURE

func _tick_explode(boss: BossGhostWitch) -> int:
    if boss.baby_state != BossGhostWitch.BabyState.EXPLODED:
        return RUNNING
    boss.baby_anim_play(&"baby/explode", false)
    # Spine 事件 "explode_hitbox_on" → 开启 BabyExplosionArea 范围伤害
    # Spine 事件 "explode_hitbox_off" → 关闭
    # Spine 事件 "realhurtbox_on" → boss._set_baby_realhurtbox(true)
    if boss.baby_anim_is_finished(&"baby/explode"):
        boss.baby_state = BossGhostWitch.BabyState.REPAIRING
        _step = Step.REPAIR
    return RUNNING

func _tick_repair(boss: BossGhostWitch) -> int:
    boss.baby_anim_play(&"baby/repair", false)
    # 修复期间 realhurtbox 保持开启，ghostfist 可以攻击核心
    if boss.baby_anim_is_finished(&"baby/repair"):
        # Spine 事件 "realhurtbox_off" → boss._set_baby_realhurtbox(false)
        # 修复完毕，核心关闭，恢复不可打中状态
        _step = Step.CHECK_PLAYER
    return RUNNING

func _tick_check_player(boss: BossGhostWitch) -> int:
    # 检测玩家是否在 BabyDetectArea 范围内
    var player_in_range: bool = false
    for body in boss._baby_detect_area.get_overlapping_bodies():
        if body.is_in_group("player"):
            player_in_range = true
            break

    if player_in_range:
        _dash_origin = boss._baby_statue.global_position
        var player := boss.get_priority_attack_target()
        _dash_target = player.global_position if player != null else _dash_origin
        boss.baby_state = BossGhostWitch.BabyState.DASHING
        boss._baby_dash_go_triggered = false
        _step = Step.DASH_TO_PLAYER
    else:
        # 玩家不在范围内，跳过冲刺，直接收招返航
        boss.baby_state = BossGhostWitch.BabyState.WINDING_UP
        _step = Step.WIND_UP
    return RUNNING

func _tick_dash(boss: BossGhostWitch, to_player: bool) -> int:
    var target := _dash_target if to_player else _dash_origin
    var baby := boss._baby_statue

    if to_player:
        # 冲刺去：先播蓄力动画，等 dash_go 事件后切到 dash_loop
        if not boss._baby_dash_go_triggered:
            boss.baby_anim_play(&"baby/dash", false)
            # Spine 事件 "dash_go" 触发前只播蓄力，不移动
            return RUNNING
        # dash_go 已触发，切到冲刺循环动画
        boss.baby_anim_play(&"baby/dash_loop", true)
    else:
        # 冲刺回：跳过蓄力，直接播冲刺循环动画
        boss.baby_anim_play(&"baby/dash_loop", true)

    # Spine 事件 "dash_hitbox_on" → 开启 BabyAttackArea
    var dir := sign(target.x - baby.global_position.x)
    baby.global_position.x += dir * boss.baby_dash_speed * get_physics_process_delta_time()

    # 冲刺期间检测碰撞伤害
    for body in boss._baby_attack_area.get_overlapping_bodies():
        if body.is_in_group("player") and body.has_method("apply_damage"):
            body.call("apply_damage", 1, baby.global_position)

    if abs(target.x - baby.global_position.x) < 10.0:
        baby.global_position.x = target.x
        boss._baby_dash_go_triggered = false  # 重置
        if to_player:
            _wait_end = Time.get_ticks_msec() + boss.baby_post_dash_wait * 1000.0
            boss.baby_state = BossGhostWitch.BabyState.POST_DASH_WAIT
            _step = Step.POST_DASH_WAIT
        else:
            boss.baby_state = BossGhostWitch.BabyState.WINDING_UP
            _step = Step.WIND_UP
    return RUNNING

func _tick_wait(boss: BossGhostWitch) -> int:
    boss.baby_anim_play(&"baby/idle", true)
    if Time.get_ticks_msec() >= _wait_end:
        boss.baby_state = BossGhostWitch.BabyState.DASHING
        _step = Step.DASH_BACK
    return RUNNING

func _tick_wind_up(boss: BossGhostWitch) -> int:
    boss.baby_anim_play(&"baby/wind_up", false)
    if boss.baby_anim_is_finished(&"baby/wind_up"):
        boss.baby_state = BossGhostWitch.BabyState.RETURNING
        _step = Step.RETURN_HOME
    return RUNNING

func _tick_return(boss: BossGhostWitch) -> int:
    boss.baby_anim_play(&"baby/return", true)
    var target_pos := boss._mark_hug.global_position
    var baby := boss._baby_statue
    var dir := (target_pos - baby.global_position).normalized()
    baby.global_position += dir * boss.baby_return_speed * get_physics_process_delta_time()

    if baby.global_position.distance_to(target_pos) < 10.0:
        baby.global_position = target_pos
        boss.baby_state = BossGhostWitch.BabyState.IN_HUG
        boss.anim_play(&"phase1/catch_baby", false)
        return SUCCESS
    return RUNNING

func interrupt(actor: Node, blackboard: Blackboard) -> void:
    _step = Step.EXPLODE
    var boss := actor as BossGhostWitch
    if boss:
        boss._baby_dash_go_triggered = false
        boss._set_hitbox_enabled(boss._baby_attack_area, false)
        boss._set_hitbox_enabled(boss._baby_explosion_area, false)
        boss._set_baby_realhurtbox(false)
    super(actor, blackboard)
```

#### ActSlowMoveToPlayer（缓慢移动兜底）

```gdscript
class_name ActSlowMoveToPlayer extends ActionLeaf

func tick(actor: Node, blackboard: Blackboard) -> int:
    var boss := actor as BossGhostWitch
    if boss == null: return FAILURE
    var player := boss.get_priority_attack_target()
    if player == null: return RUNNING

    var h_dist := abs(player.global_position.x - actor.global_position.x)
    if h_dist < 20.0:
        actor.velocity.x = 0.0
        boss.anim_play(&"phase1/idle", true)
    else:
        var dir := signf(player.global_position.x - actor.global_position.x)
        actor.velocity.x = dir * boss.slow_move_speed
        boss.face_toward(player)
        boss.anim_play(&"phase1/walk", true)
    return RUNNING  # 永远 RUNNING，让 SelectorReactive 重评估
```

---

### 8.3 Phase 2 ActionLeaf

#### ActScytheSlash（镰刀斩）

```gdscript
class_name ActScytheSlash extends ActionLeaf

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
            boss.anim_play(&"phase2/scythe_slash", false)
            _step = Step.WAIT
            return RUNNING
        Step.WAIT:
            # Spine 事件 "scythe_hitbox_on" / "scythe_hitbox_off" 驱动伤害检测
            if boss.anim_is_finished(&"phase2/scythe_slash"):
                _set_cooldown(actor, blackboard, "cd_scythe", boss.scythe_slash_cooldown)
                return SUCCESS
            return RUNNING
    return FAILURE

func _set_cooldown(actor: Node, bb: Blackboard, key: String, cd: float) -> void:
    var actor_id := str(actor.get_instance_id())
    bb.set_value(key, Time.get_ticks_msec() + cd * 1000.0, actor_id)

func interrupt(actor: Node, blackboard: Blackboard) -> void:
    _step = Step.PLAY
    super(actor, blackboard)
```

#### ActTombstoneDrop（飞天砸落 — 攻击流3）

```gdscript
## 起手施法 → 瞬移到玩家头上 → 渐显 → 悬停 → 幽灵投掷 → 下落 → 落地冲击 → 僵直
class_name ActTombstoneDrop extends ActionLeaf

enum Step {
    CAST,           # 地面起手施法动画
    TELEPORT,       # 施法播完 → 瞬移到目标位置
    APPEAR,         # 在空中渐显（慢慢出现）
    HOVER,          # 空中静止悬停（短暂压迫感）
    THROW,          # 被幽灵向下投掷的瞬间（发力表现）
    FALLING,        # 高速下落循环
    LAND,           # 砸到地面（冲击 + 范围伤害）
    STAGGER,        # 僵直
}

var _step: int = Step.CAST
var _target_pos: Vector2 = Vector2.ZERO
var _fall_timer: float = 0.0
var _fall_speed: float = 0.0
var _hover_end: float = 0.0
var _stagger_end: float = 0.0
var _hitbox_frame_count: int = 0  # 落地伤害帧计数（替代 await）

func before_run(actor: Node, _bb: Blackboard) -> void:
    _step = Step.CAST
    _hitbox_frame_count = 0

func tick(actor: Node, blackboard: Blackboard) -> int:
    var boss := actor as BossGhostWitch
    if boss == null: return FAILURE
    var dt := get_physics_process_delta_time()

    match _step:
        Step.CAST:
            boss.anim_play(&"phase2/tombstone_cast", false)
            var player := boss.get_priority_attack_target()
            if player == null: return FAILURE
            var offset_x := boss.tombstone_offset_x_range * (1.0 if randf() > 0.5 else -1.0)
            _target_pos = Vector2(
                player.global_position.x + offset_x,
                player.global_position.y - boss.tombstone_offset_y
            )
            _step = Step.TELEPORT
            return RUNNING

        Step.TELEPORT:
            if boss.anim_is_finished(&"phase2/tombstone_cast"):
                actor.global_position = _target_pos
                actor.velocity = Vector2.ZERO
                _step = Step.APPEAR
            return RUNNING

        Step.APPEAR:
            boss.anim_play(&"phase2/tombstone_appear", false)
            if boss.anim_is_finished(&"phase2/tombstone_appear"):
                _step = Step.HOVER
                _hover_end = Time.get_ticks_msec() + boss.tombstone_hover_duration * 1000.0
            return RUNNING

        Step.HOVER:
            boss.anim_play(&"phase2/tombstone_hover", true)
            if Time.get_ticks_msec() >= _hover_end:
                _step = Step.THROW
            return RUNNING

        Step.THROW:
            boss.anim_play(&"phase2/tombstone_throw", false)
            if boss.anim_is_finished(&"phase2/tombstone_throw"):
                _fall_timer = 0.0
                _fall_speed = 0.0
                _step = Step.FALLING
            return RUNNING

        Step.FALLING:
            boss.anim_play(&"phase2/tombstone_fall", true)
            _fall_timer += dt
            var t_ratio := clampf(_fall_timer / boss.tombstone_fall_duration, 0.0, 1.0)
            var eased := t_ratio * t_ratio
            _fall_speed = eased * 2000.0
            actor.velocity.y = _fall_speed

            for body in boss._ground_hitbox.get_overlapping_bodies():
                if body.is_in_group("player") and body.has_method("apply_damage"):
                    body.call("apply_damage", 1, actor.global_position)

            if actor.is_on_floor():
                _step = Step.LAND
                _hitbox_frame_count = 0
            return RUNNING

        Step.LAND:
            actor.velocity = Vector2.ZERO
            boss.anim_play(&"phase2/tombstone_land", false)
            if _hitbox_frame_count == 0:
                boss._set_hitbox_enabled(boss._ground_hitbox, true)
            elif _hitbox_frame_count >= 2:
                boss._set_hitbox_enabled(boss._ground_hitbox, false)
                _stagger_end = Time.get_ticks_msec() + boss.tombstone_stagger_duration * 1000.0
                _step = Step.STAGGER
            _hitbox_frame_count += 1
            return RUNNING

        Step.STAGGER:
            if Time.get_ticks_msec() >= _stagger_end:
                _set_cooldown(actor, blackboard, "cd_tombstone", boss.tombstone_drop_cooldown)
                return SUCCESS
            return RUNNING
    return FAILURE

func _set_cooldown(actor: Node, bb: Blackboard, key: String, cd: float) -> void:
    bb.set_value(key, Time.get_ticks_msec() + cd * 1000.0, str(actor.get_instance_id()))

func interrupt(actor: Node, blackboard: Blackboard) -> void:
    _step = Step.CAST
    _hitbox_frame_count = 0
    var boss := actor as BossGhostWitch
    if boss:
        boss._set_hitbox_enabled(boss._ground_hitbox, false)
        actor.velocity = Vector2.ZERO
    super(actor, blackboard)
```

#### ActUndeadWind（亡灵气流 — 攻击流4）

```gdscript
## 7秒内逐渐生成10只幽灵 + 随机时间生成1只精英亡灵
## 期间 realhurtbox 不可攻击
class_name ActUndeadWind extends ActionLeaf

enum Step { CAST_ENTER, SPAWNING, CAST_END, DONE }
var _step: int = Step.CAST_ENTER
var _spawn_timer: float = 0.0
var _spawn_count: int = 0
var _elite_spawned: bool = false
var _elite_spawn_time: float = 0.0  # 随机决定精英生成时机
var _type_cycle: int = 0  # 0,1,2 循环 → type1,type2,type3

func before_run(actor: Node, _bb: Blackboard) -> void:
    _step = Step.CAST_ENTER
    _spawn_timer = 0.0
    _spawn_count = 0
    _elite_spawned = false
    _elite_spawn_time = randf_range(1.0, 6.0)
    _type_cycle = 0

func tick(actor: Node, blackboard: Blackboard) -> int:
    var boss := actor as BossGhostWitch
    if boss == null: return FAILURE
    var dt := get_physics_process_delta_time()

    match _step:
        Step.CAST_ENTER:
            boss.anim_play(&"phase2/undead_wind_cast", false)
            boss._set_realhurtbox_enabled(false)  # 期间不可攻击
            _step = Step.SPAWNING
            return RUNNING
        Step.SPAWNING:
            boss.anim_play(&"phase2/undead_wind_loop", true)
            _spawn_timer += dt
            # 加速度生成：间隔随时间缩短
            var interval := lerpf(1.2, 0.3, clampf(_spawn_timer / boss.undead_wind_spawn_duration, 0.0, 1.0))
            # 简化：用计数和时间判断是否该生成下一只
            if _spawn_count < boss.undead_wind_total_count:
                var expected_count := int(_spawn_timer / interval)
                if expected_count > _spawn_count:
                    _spawn_wraith(boss)
                    _spawn_count += 1

            # 精英亡灵
            if not _elite_spawned and _spawn_timer >= _elite_spawn_time:
                _spawn_elite(boss)
                _elite_spawned = true

            if _spawn_timer >= boss.undead_wind_spawn_duration:
                _step = Step.CAST_END
            return RUNNING
        Step.CAST_END:
            boss.anim_play(&"phase2/undead_wind_end", false)
            boss._set_realhurtbox_enabled(true)  # 恢复可攻击
            if boss.anim_is_finished(&"phase2/undead_wind_end"):
                _set_cooldown(actor, blackboard, "cd_wind", boss.undead_wind_cooldown)
                return SUCCESS
            return RUNNING
    return FAILURE

func _spawn_wraith(boss: BossGhostWitch) -> void:
    var wraith: Node2D = boss._ghost_wraith_scene.instantiate()
    wraith.add_to_group("ghost_wraith")
    # 设置 type (1,2,3 循环)
    var wraith_type := (_type_cycle % 3) + 1
    _type_cycle += 1
    if wraith.has_method("setup"):
        var player := boss.get_priority_attack_target()
        wraith.call("setup", wraith_type, player, boss.global_position)
    wraith.global_position = boss.global_position
    boss.get_parent().add_child(wraith)

func _spawn_elite(boss: BossGhostWitch) -> void:
    var elite: Node2D = boss._ghost_elite_scene.instantiate()
    elite.add_to_group("ghost_elite")
    if elite.has_method("setup"):
        var player := boss.get_priority_attack_target()
        elite.call("setup", player, boss)  # 传入 boss 引用，被击杀时扣 boss HP
    elite.global_position = boss.global_position
    boss.get_parent().add_child(elite)

func _set_cooldown(actor: Node, bb: Blackboard, key: String, cd: float) -> void:
    bb.set_value(key, Time.get_ticks_msec() + cd * 1000.0, str(actor.get_instance_id()))

func interrupt(actor: Node, blackboard: Blackboard) -> void:
    _step = Step.CAST_ENTER
    var boss := actor as BossGhostWitch
    if boss: boss._set_realhurtbox_enabled(true)
    super(actor, blackboard)
```

#### ActGhostTug（幽灵拔河 — 攻击流2）

```gdscript
## 召唤幽灵拔河拉玩家到近身（≤100px）→ 结束，交由行为树下一拍进入镰刀斩
## 可被 ghostfist 打断
class_name ActGhostTug extends ActionLeaf

enum Step { CAST, PULLING, DONE }
var _step: int = Step.CAST
var _tug_instance: Node2D = null

func before_run(actor: Node, _bb: Blackboard) -> void:
    _step = Step.CAST

func tick(actor: Node, blackboard: Blackboard) -> int:
    var boss := actor as BossGhostWitch
    if boss == null: return FAILURE

    match _step:
        Step.CAST:
            boss.anim_play(&"phase2/ghost_tug_cast", false)
            # Spine 事件 "tug_spawn" 时生成拔河实例
            var player := boss.get_priority_attack_target()
            if player == null: return FAILURE
            _tug_instance = boss._ghost_tug_scene.instantiate()
            _tug_instance.add_to_group("ghost_tug")
            # 生成在玩家→Boss方向偏移位置
            var dir_to_boss: float = signf(boss.global_position.x - player.global_position.x)
            if dir_to_boss == 0.0:
                dir_to_boss = 1.0
            _tug_instance.global_position = Vector2(player.global_position.x + dir_to_boss * 60.0, player.global_position.y)
            if _tug_instance.has_method("setup"):
                _tug_instance.call("setup", player, boss, boss.ghost_tug_pull_speed)
            boss.get_parent().add_child(_tug_instance)
            _step = Step.PULLING
            return RUNNING
        Step.PULLING:
            boss.anim_play(&"phase2/ghost_tug_loop", true)
            # 检查拔河是否被打断（ghostfist 击中）
            if _tug_instance == null or not is_instance_valid(_tug_instance):
                _set_cooldown(actor, blackboard, "cd_tug", boss.ghost_tug_cooldown)
                return SUCCESS
            # 用水平距离判定玩家是否到达 100px 近战区
            var player := boss.get_priority_attack_target()
            if player == null: return RUNNING
            var h_dist := absf(player.global_position.x - boss.global_position.x)
            if h_dist <= 100.0:
                _destroy_tug()
                _set_cooldown(actor, blackboard, "cd_tug", boss.ghost_tug_cooldown)
                return SUCCESS
            return RUNNING
    return FAILURE

func _destroy_tug() -> void:
    if _tug_instance != null and is_instance_valid(_tug_instance):
        if _tug_instance.has_method("begin_despawn"):
            _tug_instance.call("begin_despawn", 0.5)
        else:
            _tug_instance.queue_free()
        _tug_instance = null

func _set_cooldown(actor: Node, bb: Blackboard, key: String, cd: float) -> void:
    bb.set_value(key, Time.get_ticks_msec() + cd * 1000.0, str(actor.get_instance_id()))

func interrupt(actor: Node, blackboard: Blackboard) -> void:
    _destroy_tug()
    _step = Step.CAST
    super(actor, blackboard)
```

#### ActSpawnGhostBomb（被动：生成自爆幽灵）

```gdscript
class_name ActSpawnGhostBomb extends ActionLeaf

func tick(actor: Node, blackboard: Blackboard) -> int:
    var boss := actor as BossGhostWitch
    if boss == null: return FAILURE
    var bomb: Node2D = boss._ghost_bomb_scene.instantiate()
    bomb.add_to_group("ghost_bomb")
    if bomb.has_method("setup"):
        var player := boss.get_priority_attack_target()
        bomb.call("setup", player, boss.ghost_bomb_light_energy)
    bomb.global_position = boss.global_position
    boss.get_parent().add_child(bomb)
    _set_cooldown(actor, blackboard, "cd_bomb", boss.ghost_bomb_interval)
    return SUCCESS  # 立即完成，不是 RUNNING

func _set_cooldown(actor: Node, bb: Blackboard, key: String, cd: float) -> void:
    bb.set_value(key, Time.get_ticks_msec() + cd * 1000.0, str(actor.get_instance_id()))
```

#### ActMoveTowardPlayer（Phase 2 移动兜底）

```gdscript
class_name ActMoveTowardPlayer extends ActionLeaf

@export var move_speed: float = 80.0

func tick(actor: Node, _bb: Blackboard) -> int:
    var boss := actor as BossGhostWitch
    if boss == null: return FAILURE
    var player := boss.get_priority_attack_target()
    if player == null:
        actor.velocity.x = 0.0
        return RUNNING

    var h_dist := abs(player.global_position.x - actor.global_position.x)
    if h_dist < 30.0:
        actor.velocity.x = 0.0
        boss.anim_play(&"phase2/idle", true)
    else:
        var dir := signf(player.global_position.x - actor.global_position.x)
        actor.velocity.x = dir * move_speed
        boss.face_toward(player)
        boss.anim_play(&"phase2/walk", true)
    return RUNNING
```

---


---

## 9. 子实例场景设计

### 9.1 GhostTug.tscn（幽灵拔河）

**节点结构：**
```
GhostTug (Node2D)  # ghost_tug.gd
├── SpineSprite    # 幽灵拔河动画
└── HitArea (Area2D)  # ghostfist 打断用检测区
    └── CollisionShape2D
```

**动画清单：**

| 动画名 | loop | 用途 |
|---|---|---|
| `appear` | false | 出场渐显（Spine 动画内控制透明度从 0→1）|
| `move_loop` | true | 拉拽中循环 |
| `hit` | false | 被 ghostfist 打中后受击 + 渐隐消失（Spine 动画内控制透明度 1→0），播完后销毁节点 |

**出场和受击消失的透明度全部由 Spine 动画控制，不用代码 tween。**

**ghost_tug.gd 核心逻辑：**

```gdscript
extends Node2D

var _player: Node2D = null
var _boss: Node2D = null
var _pull_speed: float = 400.0
var _dying: bool = false
var _appeared: bool = false

func setup(player: Node2D, boss: Node2D, pull_speed: float) -> void:
    _player = player
    _boss = boss
    _pull_speed = pull_speed

func _ready() -> void:
    # 出场动画（Spine 内控制透明度渐显）
    _play_anim(&"appear", false)

    # 连接 Spine 动画完成信号
    var spine: Node = get_node_or_null("SpineSprite")
    if spine and spine.has_signal("animation_event"):
        spine.animation_event.connect(_on_spine_event)
    if spine and spine.has_signal("animation_completed"):
        spine.animation_completed.connect(_on_anim_completed_raw)

    # HitArea 被 ghostfist 击中
    $HitArea.area_entered.connect(_on_hit)

func _on_anim_completed_raw(_spine_sprite, _track_entry) -> void:
    # appear 播完 → 切到 move_loop
    if not _appeared and not _dying:
        _appeared = true
        _play_anim(&"move_loop", true)
        return
    # hit 播完 → 销毁
    if _dying:
        queue_free()

func _on_spine_event(a1, a2, a3, a4) -> void:
    if _dying: return
    var event_name := _extract_event_name(a1, a2, a3, a4)
    if event_name == &"move":
        _pull_player_toward_boss()

func _pull_player_toward_boss() -> void:
    if _player == null or _boss == null: return
    if not is_instance_valid(_player) or not is_instance_valid(_boss): return
    var dir_x := signf(_boss.global_position.x - _player.global_position.x)
    _player.velocity.x = dir_x * _pull_speed
    if _player.has_method("set_external_control_frozen"):
        _player.call("set_external_control_frozen", true)

func _on_hit(area: Area2D) -> void:
    if _dying: return
    if not area.is_in_group("ghost_fist_hitbox"): return
    _dying = true
    _release_player()
    # 播放受击 + 渐隐动画（Spine 内控制透明度），播完后 _on_anim_completed_raw 触发 queue_free
    _play_anim(&"hit", false)

func _release_player() -> void:
    if _player and is_instance_valid(_player) and _player.has_method("set_external_control_frozen"):
        _player.call("set_external_control_frozen", false)

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
    pass  # 实际走 AnimDriverSpine / SpineSprite
```

### 9.2 GhostBomb.tscn（自爆幽灵）

**节点结构：**
```
GhostBomb (CharacterBody2D)  # ghost_bomb.gd
├── SpineSprite
├── HurtArea (Area2D)    # 被 ghostfist 消灭
│   └── CollisionShape2D
├── ExplosionArea (Area2D)  # 自爆伤害区
│   └── CollisionShape2D
└── LightArea (Area2D)      # 自爆光照区（范围比伤害区大）
    └── CollisionShape2D
```

**动画清单：**

| 动画名 | loop | 事件 | 用途 |
|---|---|---|---|
| `appear` | false | — | 出现动画 |
| `move` | true | — | S 形移动中 |
| `explode` | false | `explosion_hitbox_on`、`explosion_hitbox_off`、`light_emit` | 自爆（伤害区和光照区分开触发）|

**核心逻辑要点：**
- 出现后播放 `appear`，播完切 `move`
- S 形移动：每 2 秒检测玩家位置，用 `sin(time * frequency) * amplitude` 在 X 轴叠加蛇形偏移
- 触碰玩家 → 1 秒延迟自爆 → 播放 `explode` → Spine 事件控制伤害区和光照区
- `explosion_hitbox_on`/`off`：控制 ExplosionArea（伤害）
- `light_emit`：触发光照（EventBus 或 LightArea），光照能量 +5
- 伤害区和光照区是分开的 Area2D，光照区范围更大
- 被 ghostfist 打中 → 直接 `queue_free()`（不播爆炸，直接消失）
- Phase 2 结束时 Boss 调用 `get_tree().call_group("ghost_bomb", "queue_free")` 清除全部

**ghost_bomb.gd 核心代码示例：**

```gdscript
extends CharacterBody2D

var _player: Node2D = null
var _light_energy: float = 5.0
var _move_speed: float = 60.0
var _track_interval: float = 2.0
var _track_timer: float = 0.0
var _target_pos: Vector2 = Vector2.ZERO
var _time: float = 0.0
var _exploding: bool = false
var _appeared: bool = false

@export var s_curve_amplitude: float = 40.0
@export var s_curve_frequency: float = 2.0
@export var explode_delay: float = 1.0

func setup(player: Node2D, light_energy: float) -> void:
    _player = player
    _light_energy = light_energy

func _ready() -> void:
    add_to_group("ghost_bomb")
    _play_anim(&"appear", false)
    # 连接信号
    $HurtArea.area_entered.connect(_on_ghostfist_hit)
    $ExplosionArea.body_entered.connect(_on_touch_player)
    var spine: Node = get_node_or_null("SpineSprite")
    if spine and spine.has_signal("animation_completed"):
        spine.animation_completed.connect(_on_anim_completed_raw)
    if spine and spine.has_signal("animation_event"):
        spine.animation_event.connect(_on_spine_event)

func _on_anim_completed_raw(_ss, _te) -> void:
    if not _appeared and not _exploding:
        _appeared = true
        _update_target()
        _play_anim(&"move", true)
        return
    if _exploding:
        queue_free()

func _physics_process(dt: float) -> void:
    if _exploding or not _appeared: return
    _time += dt
    _track_timer += dt
    if _track_timer >= _track_interval:
        _track_timer = 0.0
        _update_target()
    # S 形移动
    var dir := (_target_pos - global_position).normalized()
    var s_offset := sin(_time * s_curve_frequency) * s_curve_amplitude
    velocity = dir * _move_speed + Vector2(s_offset, 0)
    move_and_slide()

func _on_touch_player(body: Node2D) -> void:
    if _exploding: return
    if not body.is_in_group("player"): return
    _start_explode()

func _start_explode() -> void:
    _exploding = true
    velocity = Vector2.ZERO
    # 1秒延迟后播放爆炸动画
    await get_tree().create_timer(explode_delay).timeout
    _play_anim(&"explode", false)

func _on_spine_event(a1, a2, a3, a4) -> void:
    var event_name := _extract_event_name(a1, a2, a3, a4)
    match event_name:
        &"explosion_hitbox_on":
            _set_area_enabled($ExplosionArea, true)
        &"explosion_hitbox_off":
            _set_area_enabled($ExplosionArea, false)
        &"light_emit":
            # 释放光照能量（与 lightflower 同机制）
            if EventBus:
                EventBus.emit_signal("healing_burst", _light_energy)

func _on_ghostfist_hit(area: Area2D) -> void:
    if area.is_in_group("ghost_fist_hitbox"):
        queue_free()

func _update_target() -> void:
    if _player and is_instance_valid(_player):
        _target_pos = _player.global_position

func _set_area_enabled(area: Area2D, enabled: bool) -> void:
    area.set_deferred("monitoring", enabled)
    for child in area.get_children():
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
    pass  # 实际走 AnimDriverSpine / SpineSprite
```

### 9.3 GhostWraith.tscn（亡灵气流幽灵，3 型合一）

**节点结构：**
```
GhostWraith (Node2D)  # ghost_wraith.gd
├── SpineSprite
└── HitArea (Area2D)   # 碰到玩家伤害 + 被 ghostfist 检测
    └── CollisionShape2D
```

**核心逻辑要点：**
- `setup(type: int, player: Node2D, spawn_pos: Vector2)`：type 决定播放 `type1/move`、`type2/move`、`type3/move`
- X 轴向玩家方向平移，速度偏慢（~80px/s）
- 碰到玩家 → `player.apply_damage(1, global_position)`
- 被 ghostfist 打中 → 播放对应 type 的死亡动画（`type1/death`、`type2/death`、`type3/death`）→ 动画播完后 `queue_free()`
- 最多存活 10 秒 → 自动 `queue_free()`

**动画清单：**

| 动画名 | loop | 用途 |
|---|---|---|
| `type1/move` | true | 第1型移动 |
| `type2/move` | true | 第2型移动 |
| `type3/move` | true | 第3型移动 |
| `type1/death` | false | 第1型被打消失 |
| `type2/death` | false | 第2型被打消失 |
| `type3/death` | false | 第3型被打消失 |

**被打消失代码示例：**

```gdscript
var _type: int = 1
var _dying: bool = false

func _on_hit_by_ghostfist(area: Area2D) -> void:
    if _dying: return
    if not area.is_in_group("ghost_fist_hitbox"): return
    _dying = true
    set_physics_process(false)  # 停止移动
    var death_anim := StringName("type%d/death" % _type)
    _play_anim(death_anim, false)

func _on_death_anim_finished() -> void:
    queue_free()
```

### 9.4 GhostElite.tscn（精英亡灵）

**节点结构：**
```
GhostElite (Node2D)  # ghost_elite.gd
├── SpineSprite
├── HitArea (Area2D)     # 被 ghostfist 击杀
│   └── CollisionShape2D
└── AttackArea (Area2D)  # 范围挥击
    └── CollisionShape2D
```

**核心逻辑要点：**
- HP = 1，被 ghostfist 打中 → 播放 `death` 动画 → 动画播完后 `queue_free()` + 调用 `boss.apply_real_damage(1)` 扣 Boss 血
- 向玩家方向平移（同 GhostWraith 速度），播放 `move` 动画
- 检测到玩家在范围内时发动挥击（cd=1s），播放 `attack` 动画
- 挥击：Spine 事件 `attack_hitbox_on` / `attack_hitbox_off` 控制 AttackArea 启闭
- 一次攻击流中只能生成 1 只

**动画清单：**

| 动画名 | loop | 事件 | 用途 |
|---|---|---|---|
| `move` | true | — | 向玩家移动 |
| `attack` | false | `attack_hitbox_on`、`attack_hitbox_off` | 范围挥击 |
| `death` | false | — | 被 ghostfist 打中后死亡消失 |

**核心代码示例：**

```gdscript
extends Node2D

var _player: Node2D = null
var _boss: Node2D = null
var _dying: bool = false
var _attacking: bool = false
var _attack_cd_end: float = 0.0
var _move_speed: float = 80.0
var _detect_range: float = 100.0

func setup(player: Node2D, boss: Node2D) -> void:
    _player = player
    _boss = boss

func _physics_process(dt: float) -> void:
    if _dying or _attacking: return
    if _player == null or not is_instance_valid(_player): return

    var h_dist := abs(global_position.x - _player.global_position.x)

    # 检测到玩家在范围内 → 挥击
    if h_dist <= _detect_range and Time.get_ticks_msec() >= _attack_cd_end:
        _attacking = true
        _play_anim(&"attack", false)
        return

    # 向玩家移动
    var dir := signf(_player.global_position.x - global_position.x)
    global_position.x += dir * _move_speed * dt
    _play_anim(&"move", true)

func _on_attack_anim_finished() -> void:
    _attacking = false
    _attack_cd_end = Time.get_ticks_msec() + 1000.0  # 1s cd

func _on_hit_by_ghostfist(area: Area2D) -> void:
    if _dying: return
    if not area.is_in_group("ghost_fist_hitbox"): return
    _dying = true
    set_physics_process(false)
    _play_anim(&"death", false)

func _on_death_anim_finished() -> void:
    if _boss and is_instance_valid(_boss):
        _boss.apply_real_damage(1)
    queue_free()
```

---


---

## 10. Phase 1→2 过渡流程

### 10.1 触发条件

`hp <= phase2_hp_threshold` (hp <= 20) 时调用 `_begin_phase_transition(Phase.PHASE2)`。

### 10.2 过渡步骤（时序严格）

```
1. hp_locked = true，_phase_transitioning = true
2. 中断当前攻击流（行为树检测 _phase_transitioning → ActWaitTransition 接管）
3. 如果婴儿石像不在怀中（baby_state != IN_HUG）：
   → 立即中断攻击流，婴儿播放 baby/phase1_to_phase2
   → 等待 baby/phase1_to_phase2 播完
   → baby_state = HALO
   → BabyBodyBox disabled（永久）
   → BabyRealHurtbox enabled（永久）
   → 婴儿飞向 Mark2D_Hale 位置
   → 到达后 → 步骤 4
4. 如果婴儿在怀中：
   → 婴儿直接播放 baby/phase1_to_phase2
   → 同步骤 3 的 box 切换
   → 婴儿移动到 Mark2D_Hale
   → 到达后 → 步骤 5
5. 光环到达 hale 位置后：
   → 魔女石像播放 phase1/phase1_to_phase2
   → 播完后：魔女动画切到 phase2/idle
   → BabyStatue.visible = false（光环视觉已包含在魔女 Phase2 动画中）
   → RealHurtbox（Boss 本体的）绑定到魔女 hale 骨骼，enabled
   → current_phase = Phase.PHASE2
   → _phase_transitioning = false
   → hp_locked = false
```

### 10.3 ActWaitTransition（变身等待 Action）

```gdscript
class_name ActWaitTransition extends ActionLeaf

func tick(actor: Node, _bb: Blackboard) -> int:
    var boss := actor as BossGhostWitch
    if boss == null: return FAILURE
    if boss._phase_transitioning:
        return RUNNING  # 变身动画还没播完，保持 RUNNING
    return FAILURE  # 变身结束，让 CondPhaseTransitioning 失败，退出此分支
```

---

> Spine 动画事件清单和攻击参数总表已统合至第 19、20 节（含全三阶段）。

---
