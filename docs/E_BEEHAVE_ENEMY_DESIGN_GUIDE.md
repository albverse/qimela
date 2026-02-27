# E_BEEHAVE_ENEMY_DESIGN_GUIDE.md

# Beehave 敌人行为设计指南 —— AI 构建行为树专用规范文档

> 适用项目：Qimela (chain) / Godot 4.5 / Beehave 2.9.x
> 本文档的目标：当你设计好一个 Monster 或 Boss 的行为规范后，把本文档 + 填好的规范表 + `BEEHAVE_REFERENCE.md` 一起交给 AI，AI 就能正确构建完整的 Beehave 行为树。

---

## 一、哪些敌人应该用 Beehave？

### 决策矩阵

| 敌人类型 | 行为复杂度 | 是否推荐 Beehave | 理由 |
|----------|-----------|------------------|------|
| **简单 Monster**（如 MonsterWalk、MonsterFly） | 极低（巡逻+碰墙转向） | **不推荐** | `_do_move()` 几行代码就搞定，引入行为树是过度工程 |
| **中等 Monster**（如 MonsterHostile、未来有追踪/攻击的怪物） | 中（追踪+攻击+多状态） | **推荐** | 状态切换超过 3 个、且需要条件优先级评估时，行为树比手写 if-else 可维护性强很多 |
| **Chimera**（如 ChimeraA、ChimeraStoneSnake） | 低~中 | **按复杂度决定** | ChimeraA 只有跟随/漫游两个状态，不需要。ChimeraStoneSnake 有检测+攻击+冷却，行为树更清晰但不是必须。未来如果 Chimera 有多种主动技能，则推荐 |
| **Boss** | 高（多阶段+多技能+防御模式+动画驱动） | **强烈推荐** | Boss 是行为树的主战场，多阶段、多技能优先级、冷却管理、防御模式切换，没有行为树几乎不可能维护 |

### 总结原则

```
行为分支 ≤ 2 个 → 不用 Beehave，直接 _do_move() / _physics_process()
行为分支 3~5 个 + 有条件优先级 → 推荐 Beehave
行为分支 > 5 个 + 多阶段 + 技能冷却 → 强烈推荐 Beehave
```

### 现有怪物是否需要改造？

**不推荐统一改造现有怪物**。原因：

1. 现有 MonsterWalk/Fly/Neutral 等行为极其简单，改成行为树增加了文件数量和认知成本，零收益
2. MonsterBase 的 `_physics_process` → `_do_move()` 模式对简单怪物工作良好
3. 改造需要同时修改所有子类的场景文件，工作量大且容易引入 bug

**推荐的渐进策略：**

1. **现有简单怪物保持不变**（MonsterWalk, MonsterFly, MonsterNeutral, MonsterHand 等）
2. **MonsterHostile 可选改造**（未来需要追踪/攻击 AI 时考虑）
3. **新增的中等复杂度怪物从一开始就用 Beehave**
4. **所有 Boss 必须用 Beehave**
5. **Chimera 如果未来增加主动攻击/多技能时再改造**

---

## 二、项目特有的战斗系统约束（AI 必读）

### 2.1 伤害系统 (HitData)

项目使用 `HitData` 类传递命中信息：

```gdscript
# combat/hit_data.gd
class Flags:
    const NONE: int = 0
    const STAGGER: int = 1      # 硬直（短暂眩晕）
    const KNOCKBACK: int = 2    # 击退
    const PIERCE: int = 4       # 穿透护甲

var damage: int = 1
var source: Node2D = null       # 攻击者
var weapon_id: StringName = &"" # 武器标识
var flags: int = Flags.NONE
```

### 2.2 武器与防御交互规则

| 武器 | weapon_id | 默认 flags | 对普通状态怪物 | 对虚弱状态怪物 | 对防御模式Boss（未来） |
|------|----------|------------|--------------|--------------|---------------------|
| **Chain（锁链）** | `"chain"` | `NONE` | 1点伤害，不链接 | 不扣血（hp_locked），可链接 | **无法穿透防御**，0伤害 |
| **Ghost Fist（鬼拳）** | `"ghost_fist"` | `STAGGER` | 1点伤害+硬直 | 闪白+硬直，不扣血 | **穿透护甲**（PIERCE），无视防御模式 |
| **Sword（剑）** | `"sword"` | `NONE` | 1点伤害 | 不扣血 | 按flags决定 |
| **Knife（刀）** | `"knife"` | `NONE` | 1点伤害 | 不扣血 | 按flags决定 |

### 2.3 怪物/Boss 防御状态设计空间

当前项目的防御机制基于 `hp_locked`（虚弱状态锁血）。对于 Boss，需要扩展以下防御概念：

| 防御模式 | Blackboard Key 建议 | 行为 | Chain 效果 | Ghost Fist 效果 |
|---------|---------------------|------|-----------|----------------|
| **NORMAL（普通）** | `defense_mode = 0` | 无特殊防御 | 正常伤害 | 正常伤害+硬直 |
| **GUARD（格挡）** | `defense_mode = 1` | 减伤或免伤，动画表现为格挡姿势 | 0伤害，链反弹 | **穿透**，正常伤害 |
| **ARMOR（盔甲）** | `defense_mode = 2` | 完全免疫普通攻击 | 0伤害 | 带 PIERCE flag 时正常伤害，否则0伤害 |
| **SUPER_ARMOR（霸体）** | `defense_mode = 3` | 不被硬直/击退打断，正常受伤 | 正常伤害，不中断动作 | 正常伤害，不中断动作（STAGGER无效） |
| **INVULNERABLE（无敌）** | `defense_mode = 4` | 阶段切换过场，完全无敌 | 0伤害 | 0伤害 |

> **实现建议**：在 Boss 的 `apply_hit()` 重写中，根据 `defense_mode` + `hit.flags` + `hit.weapon_id` 决定伤害和打断效果。

### 2.4 眩晕/虚弱系统（Beehave 需要感知的状态）

Boss 的行为树需要读取以下状态：

| 状态 | 变量 | 说明 | 行为树中的用途 |
|------|------|------|--------------|
| HP 百分比 | `hp / max_hp` | 当前生命值比例 | 阶段切换条件 |
| 虚弱 | `weak` | HP 降至 weak_hp 以下 | Boss 可选是否进入虚弱（Boss 可能 weak_hp=0） |
| 眩晕 | `stunned_t > 0` | 被硬直/光花/治愈爆发击中 | 被眩晕时中断当前行为 |
| 被链接 | `is_linked()` | 被锁链连接 | Boss 可能有挣脱机制 |
| 防御模式 | `defense_mode` | 当前防御状态 | 决定是否接受伤害/是否可被打断 |

---

## 三、敌人行为规范模板

以下是完整的行为规范模板。填写此模板后，AI 可以直接据此构建行为树。

---

### SECTION A：基础信息

```yaml
# ============================================
# 敌人行为规范 v1.0
# ============================================

entity_name: ""           # 实体名称，例如 "BossPhantom"
class_name: ""            # GDScript class_name，例如 "BossPhantom"
base_class: ""            # 继承基类：MonsterBase / ChimeraBase / 自定义BossBase
entity_type: ""           # MONSTER / CHIMERA / BOSS
species_id: ""            # 物种ID，例如 "boss_phantom"
attribute_type: ""        # NORMAL / LIGHT / DARK
size_tier: ""             # SMALL / MEDIUM / LARGE

# HP系统
max_hp: 0
weak_hp: 0                # 0 = 无虚弱状态（Boss常见）
vanish_fusion_required: 0 # 0 = 不可被泯灭融合击杀

# 移动
move_type: ""             # GROUND / FLY / STATIC（不移动）
move_speed: 0.0           # 像素/秒
gravity: 0.0              # 仅地面单位
```

---

### SECTION B：阶段定义（Boss 专用，普通怪物跳过）

```yaml
phases:
  - id: "phase_1"
    name: "Phase 1 - 常规战斗"
    hp_range: [1.0, 0.6]       # HP百分比区间 [上限, 下限)
    description: "Boss处于正常状态，使用基础技能组合"
    defense_mode: "NORMAL"      # 此阶段的默认防御模式
    bgm_change: false           # 是否切换BGM
    phase_enter_animation: ""   # 进入阶段时播放的过场动画（可空）
    phase_enter_invulnerable: false  # 进入阶段时是否短暂无敌

  - id: "phase_2"
    name: "Phase 2 - 狂暴"
    hp_range: [0.6, 0.3]
    description: "Boss加速，解锁新技能"
    defense_mode: "SUPER_ARMOR"
    bgm_change: true
    phase_enter_animation: "rage_roar"
    phase_enter_invulnerable: true   # 吼叫动画期间无敌

  - id: "phase_3"
    name: "Phase 3 - 濒死"
    hp_range: [0.3, 0.0]
    description: "Boss进入盔甲模式，只有鬼拳能打穿"
    defense_mode: "ARMOR"
    bgm_change: false
    phase_enter_animation: "armor_up"
    phase_enter_invulnerable: true
```

---

### SECTION C：技能/行为定义

每个技能/行为都需要填写以下完整信息。**这是最关键的部分**。

```yaml
skills:
  - id: "skill_melee_slash"
    name: "近战斩击"
    type: "ATTACK"            # ATTACK / MOVEMENT / DEFENSE / UTILITY / PASSIVE
    priority: 1               # 数字越小优先级越高（在行为树中排越前面）
    available_phases: ["phase_1", "phase_2"]  # 在哪些阶段可用

    # === 触发条件 ===
    conditions:
      - type: "RANGE"
        param: "melee"        # melee / mid_range / long_range / custom
        value: 80.0           # 像素距离（水平距离，不含Y轴）
        check_axis: "X_ONLY"  # X_ONLY（推荐2D横版）/ XY（全距离）
      - type: "COOLDOWN"
        value: 2.0            # 冷却时间（秒）
      - type: "PLAYER_STATE"
        param: "on_ground"    # 可选：on_ground / in_air / any
      - type: "CUSTOM"
        description: "玩家未处于无敌状态"
        blackboard_key: ""    # 可空，由AI实现

    # === 伤害 ===
    damage:
      amount: 2
      flags: ["STAGGER"]          # NONE / STAGGER / KNOCKBACK / PIERCE
      weapon_id: "boss_slash"     # 自定义武器标识
      hit_count: 1                # 单次攻击的命中次数
      hit_interval: 0.0           # 多段攻击的间隔（秒）

    # === 动画 ===
    animation:
      name: "slash_attack"              # Spine 动画名称
      track: 0                          # Spine Track（0=全身, 1=上半身覆盖）
      duration: 0.8                     # 动画总时长（秒）
      loop: false                       # 是否循环
      play_mode: "FULLBODY_EXCLUSIVE"   # FULLBODY_EXCLUSIVE / OVERLAY_UPPER / OVERLAY_CONTEXT

      # 关键帧事件（Spine Event 或手动时间点）
      events:
        - time: 0.0
          type: "ANIM_START"
          description: "开始蓄力动作"
        - time: 0.3
          type: "HITBOX_ON"
          description: "开启伤害判定区域"
          hitbox_id: "slash_hitbox"      # 对应的 Area2D 名称
        - time: 0.5
          type: "HITBOX_OFF"
          description: "关闭伤害判定"
        - time: 0.8
          type: "ANIM_END"
          description: "动画结束，可以切换到下一个行为"

    # === 可打断性 ===
    interruptibility:
      by_stagger: false           # 被硬直打断？
      by_knockback: false         # 被击退打断？
      by_chain_hit: false         # 被锁链命中打断？
      by_phase_change: true       # 阶段切换时打断？
      during_windup: true         # 蓄力阶段可打断？（time < HITBOX_ON 时间）
      during_active: false        # 攻击判定阶段可打断？
      during_recovery: true       # 收招阶段可打断？（time > HITBOX_OFF 时间）

    # === 行为树节点建议 ===
    beehave_hint:
      node_type: "ActionLeaf"     # ActionLeaf / ConditionLeaf
      cooldown_method: "SELF_MANAGED"  # SELF_MANAGED（推荐）/ DECORATOR
      returns_running: true       # tick期间是否返回RUNNING？
      running_frames: "duration"  # 动画播放期间持续RUNNING，播完返回SUCCESS
      failure_on_interrupt: true  # 被打断时返回FAILURE？

    # === 移动 ===
    movement_during_skill:
      type: "NONE"                # NONE / DASH_FORWARD / DASH_BACKWARD / SLIDE / CUSTOM
      distance: 0.0
      speed: 0.0
      description: ""

    # === 特殊效果 ===
    special_effects:
      - type: "SCREEN_SHAKE"
        at_event: "HITBOX_ON"
        intensity: 0.5
      - type: "VFX"
        at_event: "HITBOX_ON"
        vfx_scene: "res://vfx/slash_effect.tscn"

  # ─────────────────────────────────────

  - id: "skill_ranged_shot"
    name: "远程射击"
    type: "ATTACK"
    priority: 2
    available_phases: ["phase_1", "phase_2", "phase_3"]

    conditions:
      - type: "RANGE"
        param: "long_range"
        value: 300.0
        check_axis: "X_ONLY"
      - type: "NOT_RANGE"
        param: "melee"
        value: 80.0
        description: "不在近战范围内（用InverterDecorator包装近战距离条件）"
      - type: "COOLDOWN"
        value: 3.0

    damage:
      amount: 1
      flags: ["NONE"]
      weapon_id: "boss_bullet"
      hit_count: 3
      hit_interval: 0.2
      projectile: true                    # 是否为投射物
      projectile_speed: 400.0
      projectile_scene: "res://scene/boss_bullet.tscn"

    animation:
      name: "ranged_attack"
      track: 0
      duration: 1.2
      loop: false
      play_mode: "FULLBODY_EXCLUSIVE"
      events:
        - time: 0.0
          type: "ANIM_START"
        - time: 0.4
          type: "PROJECTILE_SPAWN"
          description: "生成第1颗子弹"
        - time: 0.6
          type: "PROJECTILE_SPAWN"
          description: "生成第2颗子弹"
        - time: 0.8
          type: "PROJECTILE_SPAWN"
          description: "生成第3颗子弹"
        - time: 1.2
          type: "ANIM_END"

    interruptibility:
      by_stagger: true
      by_knockback: true
      by_chain_hit: true
      by_phase_change: true
      during_windup: true
      during_active: true
      during_recovery: true

    beehave_hint:
      node_type: "ActionLeaf"
      cooldown_method: "SELF_MANAGED"
      returns_running: true
      running_frames: "duration"
      failure_on_interrupt: true

    movement_during_skill:
      type: "NONE"

    special_effects: []

  # ─────────────────────────────────────

  - id: "behavior_chase"
    name: "追击玩家"
    type: "MOVEMENT"
    priority: 10                  # 低优先级，技能不可用时才追
    available_phases: ["phase_1", "phase_2", "phase_3"]

    conditions:
      - type: "PLAYER_DETECTED"
        detection_range: 500.0

    damage: null                  # 追击本身无伤害

    animation:
      name: "run"                 # 或 "walk"
      track: 0
      duration: -1                # -1 = 无限循环
      loop: true
      play_mode: "FULLBODY_EXCLUSIVE"
      events: []

    interruptibility:
      by_stagger: true
      by_knockback: true
      by_chain_hit: true
      by_phase_change: true
      during_windup: false
      during_active: true         # 追击随时可被更高优先级技能打断
      during_recovery: false

    beehave_hint:
      node_type: "ActionLeaf"
      cooldown_method: "NONE"
      returns_running: true
      running_frames: "always"    # 永远返回RUNNING（到达目标也不返回SUCCESS）
      failure_on_interrupt: false  # 被打断不算失败

    movement_during_skill:
      type: "MOVE_TO_PLAYER"
      speed: 200.0
      stop_distance: 60.0
      check_axis: "X_ONLY"       # 只检查水平距离，防止Y轴误判

    special_effects: []

  # ─────────────────────────────────────

  - id: "behavior_patrol"
    name: "巡逻（兜底行为）"
    type: "MOVEMENT"
    priority: 99                  # 最低优先级
    available_phases: ["phase_1", "phase_2", "phase_3"]

    conditions: []                # 无条件，作为兜底

    damage: null

    animation:
      name: "walk"
      track: 0
      duration: -1
      loop: true
      play_mode: "FULLBODY_EXCLUSIVE"
      events: []

    interruptibility:
      by_stagger: true
      by_knockback: true
      by_chain_hit: true
      by_phase_change: true
      during_windup: false
      during_active: true
      during_recovery: false

    beehave_hint:
      node_type: "ActionLeaf"
      cooldown_method: "NONE"
      returns_running: true
      running_frames: "always"
      failure_on_interrupt: false

    movement_during_skill:
      type: "PATROL"
      speed: 70.0
      patrol_type: "WALL_BOUNCE"  # WALL_BOUNCE / WAYPOINT / RANDOM_WANDER
      description: "碰墙转向的基础巡逻"

    special_effects: []

  # ─────────────────────────────────────

  - id: "defense_guard"
    name: "格挡防御"
    type: "DEFENSE"
    priority: 0                   # 最高优先级（防御条件满足时优先执行）
    available_phases: ["phase_2", "phase_3"]

    conditions:
      - type: "CUSTOM"
        description: "检测到玩家正在攻击（攻击动画播放中）或远程投射物接近"
      - type: "COOLDOWN"
        value: 5.0                # 防御冷却

    damage: null

    animation:
      name: "guard_stance"
      track: 0
      duration: 2.0               # 格挡姿势持续时间
      loop: false
      play_mode: "FULLBODY_EXCLUSIVE"
      events:
        - time: 0.0
          type: "DEFENSE_MODE_ON"
          defense_mode: "GUARD"
          description: "开启格挡模式"
        - time: 2.0
          type: "DEFENSE_MODE_OFF"
          defense_mode: "NORMAL"
          description: "格挡结束，恢复普通模式"

    interruptibility:
      by_stagger: false           # 格挡不被硬直打断
      by_knockback: false
      by_chain_hit: false
      by_phase_change: true
      during_windup: false
      during_active: false        # 格挡期间不可打断
      during_recovery: true

    beehave_hint:
      node_type: "ActionLeaf"
      cooldown_method: "SELF_MANAGED"
      returns_running: true
      running_frames: "duration"
      failure_on_interrupt: true

    movement_during_skill:
      type: "NONE"

    special_effects:
      - type: "VFX"
        at_event: "DEFENSE_MODE_ON"
        vfx_scene: "res://vfx/guard_shield.tscn"
```

---

### SECTION D：受击反应定义

描述被不同武器击中时的表现差异。

```yaml
hit_reactions:
  # 被锁链命中
  chain_hit:
    normal_state:
      damage: 1
      reaction: "FLASH"            # FLASH / STAGGER / KNOCKBACK / NONE
      can_link: false              # 普通状态不可链接
      description: "闪白，扣1HP"
    weak_state:
      damage: 0                    # hp_locked
      reaction: "FLASH"
      can_link: true
      description: "闪白不扣血，可被链接"
    guard_state:
      damage: 0
      reaction: "DEFLECT"         # 锁链被弹开
      can_link: false
      description: "锁链被弹开，无伤害"
      deflect_animation: "chain_deflect"  # Boss播放弹开动画（可选）
    armor_state:
      damage: 0
      reaction: "NONE"
      can_link: false
      description: "完全无效"

  # 被鬼拳命中
  ghost_fist_hit:
    normal_state:
      damage: 1
      reaction: "STAGGER"
      stagger_time: 0.1
      description: "硬直0.1秒"
    weak_state:
      damage: 0
      reaction: "STAGGER"
      stagger_time: 0.1
      description: "闪白+硬直，不扣血"
    guard_state:
      damage: 1                    # 鬼拳穿透格挡！
      reaction: "GUARD_BREAK"
      description: "穿透格挡，造成伤害，可能破防"
      guard_break_threshold: 3     # 连续命中3次后破防
      guard_break_animation: "guard_broken"
    armor_state:
      damage: 1                    # 鬼拳（带PIERCE）穿透盔甲
      reaction: "STAGGER"
      stagger_time: 0.05
      requires_flag: "PIERCE"      # 必须带PIERCE flag
      description: "穿透盔甲造成伤害"

  # 被剑命中
  sword_hit:
    normal_state:
      damage: 1
      reaction: "FLASH"
    guard_state:
      damage: 0
      reaction: "DEFLECT"
    armor_state:
      damage: 0
      reaction: "NONE"

  # 被刀命中
  knife_hit:
    normal_state:
      damage: 1
      reaction: "FLASH"
    guard_state:
      damage: 0
      reaction: "DEFLECT"
    armor_state:
      damage: 0
      reaction: "NONE"

  # 被雷花/治愈爆发击中
  environmental_hit:
    thunder_stun:
      stun_time: 2.0
      applies_to_guard: true       # 雷电可穿透格挡
      description: "雷击眩晕，无视格挡"
    healing_burst_stun:
      stun_time: 3.0
      applies_to_guard: true
      description: "治愈爆发眩晕，无视格挡"
```

---

### SECTION E：动画状态机定义

描述 Spine2D 动画的完整配置。

```yaml
animations:
  # 通用动画
  locomotion:
    idle:
      spine_name: "idle"
      track: 0
      loop: true
      can_be_interrupted: true
    walk:
      spine_name: "walk"
      track: 0
      loop: true
      can_be_interrupted: true
    run:
      spine_name: "run"
      track: 0
      loop: true
      can_be_interrupted: true

  # 受击动画
  reactions:
    hurt:
      spine_name: "hurt"
      track: 0
      loop: false
      duration: 0.3
      play_mode: "FULLBODY_EXCLUSIVE"
      must_complete: false        # 可以被下一次受击覆盖
    death:
      spine_name: "death"
      track: 0
      loop: false
      duration: 1.5
      play_mode: "FULLBODY_EXCLUSIVE"
      must_complete: true         # 必须播放完毕
    stagger:
      spine_name: "stagger"
      track: 0
      loop: false
      duration: 0.15
      play_mode: "FULLBODY_EXCLUSIVE"
      must_complete: true

  # 阶段过渡动画
  phase_transitions:
    rage_roar:
      spine_name: "rage_roar"
      track: 0
      loop: false
      duration: 2.0
      play_mode: "FULLBODY_EXCLUSIVE"
      must_complete: true         # 过渡动画必须播放完
      invulnerable_during: true   # 播放期间无敌

  # 技能动画（和SECTION C中的animation字段对应）
  # 这里可以补充更多Spine层级相关的细节
  skill_animations:
    slash_attack:
      spine_name: "slash_attack"
      track: 0
      mix_duration: 0.1          # 与前一个动画的混合时长
      events:                     # Spine Events（骨骼动画内嵌事件）
        - name: "hit_on"
          description: "开启命中检测"
        - name: "hit_off"
          description: "关闭命中检测"
        - name: "sfx_whoosh"
          description: "播放挥砍音效"
```

---

### SECTION F：Blackboard 数据契约

列出行为树运行时需要的所有 Blackboard 键值。

```yaml
blackboard_keys:
  # === 由 ConditionLeaf 写入，ActionLeaf 读取 ===
  player:
    type: "Node2D"
    written_by: "自给自足的ConditionLeaf（每个Condition自己感知玩家位置）"
    read_by: "ActionLeaf（如MoveToPlayer、攻击技能）"
    lifetime: "每帧更新（不跨分支依赖）"
    note: "重要：遵循beehave最佳实践，每个ConditionLeaf自己用get_nodes_in_group('player')感知，不依赖其他分支写入的值"

  player_distance_x:
    type: "float"
    written_by: "ConditionLeaf"
    read_by: "ActionLeaf"
    lifetime: "每帧更新"

  # === 由 ActionLeaf 自管理 ===
  cooldown_melee_slash:
    type: "float"
    written_by: "MeleeSlashAction（技能完成后写入冷却结束时间戳）"
    read_by: "MeleeSlashAction（tick开头检查是否在冷却中）"
    lifetime: "持久（不受interrupt影响）"
    note: "使用Time.get_ticks_msec()作为时间基准"

  cooldown_ranged_shot:
    type: "float"
    written_by: "RangedShotAction"
    read_by: "RangedShotAction"
    lifetime: "持久"

  # === 由阶段管理写入 ===
  current_phase:
    type: "int"
    written_by: "PhaseCheckCondition / Boss主脚本"
    read_by: "各阶段条件节点"
    lifetime: "持久，阶段切换时更新"

  defense_mode:
    type: "int"
    written_by: "DefenseAction / Boss主脚本"
    read_by: "apply_hit() 重写"
    lifetime: "持久"
```

---

### SECTION G：行为树结构预览（可选，帮助AI确认理解）

这一节可以用伪树描述你期望的大致结构，AI 会据此生成具体代码。

```
BeehaveTree
└── SelectorReactiveComposite [RootSelector]

    ├── SequenceReactiveComposite [Phase3Seq] (priority: highest)
    │   ├── IsHPBelowCondition (threshold=0.3)
    │   └── SelectorReactiveComposite [Phase3Skills]
    │       ├── [Phase3专属技能序列...]
    │       ├── [追击]
    │       └── [巡逻]

    ├── SequenceReactiveComposite [Phase2Seq]
    │   ├── IsHPBelowCondition (threshold=0.6)
    │   └── SelectorReactiveComposite [Phase2Skills]
    │       ├── [Phase2专属技能序列...]
    │       ├── [追击]
    │       └── [巡逻]

    └── SelectorReactiveComposite [Phase1Skills] (default)
        ├── [Phase1技能序列...]
        ├── [追击]
        └── [巡逻]
```

---

## 四、AI 构建行为树的完整检查清单

当 AI 收到本文档 + 填写好的规范表 + `BEEHAVE_REFERENCE.md` 后，应按以下顺序工作：

### 4.1 预检查

- [ ] 确认 Beehave 插件已安装（`addons/beehave/` 目录存在）
- [ ] 确认 `project.godot` 的 `[autoload]` 包含 `BeehaveGlobalDebugger` 和 `BeehaveGlobalMetrics`
- [ ] 确认 Godot 版本为 4.5.x，Beehave 版本为 2.9.x

### 4.2 创建文件结构

```
scene/enemies/{entity_name}/
├── {entity_name}.tscn              # 主场景
├── {entity_name}.gd                # 主脚本（继承MonsterBase/自定义BossBase）
├── bt_{entity_name}.tscn           # 行为树场景
├── conditions/
│   ├── is_player_detected.gd       # ConditionLeaf: 检测玩家
│   ├── is_in_melee_range.gd        # ConditionLeaf: 近战范围
│   ├── is_hp_below.gd              # ConditionLeaf: HP阈值（阶段检查）
│   └── ...
├── actions/
│   ├── melee_slash_action.gd       # ActionLeaf: 近战斩击
│   ├── ranged_shot_action.gd       # ActionLeaf: 远程射击
│   ├── move_to_player_action.gd    # ActionLeaf: 追击
│   ├── patrol_action.gd            # ActionLeaf: 巡逻
│   ├── guard_action.gd             # ActionLeaf: 格挡
│   └── ...
└── hitboxes/
    └── ...                          # 攻击判定区域场景
```

### 4.3 构建行为树的关键规则

1. **顶层必须是 SelectorReactiveComposite**（动态优先级评估）
2. **每个技能序列用 SequenceReactiveComposite**（每帧重检条件）
3. **冷却在 ActionLeaf 内自管理**（不用 CooldownDecorator）
4. **每个 ConditionLeaf 自给自足感知**（不依赖其他分支 Blackboard）
5. **追击 Action 永远返回 RUNNING**（到达目标停止移动但不返回 SUCCESS）
6. **兜底巡逻放最后**（永远 RUNNING）
7. **高优先级技能完成后设置冷却**（给低优先级行为执行窗口）
8. **不要在 .tscn 中用 type="BeehaveTree"**（必须用 type="Node" + script=）

### 4.4 .tscn 场景构建规则

```ini
# 每个 Beehave 节点必须这样写：
[node name="BeehaveTree" type="Node" parent="."]
script = ExtResource("bt_tree")

# 对应的 ext_resource：
[ext_resource type="Script" path="res://addons/beehave/nodes/beehave_tree.gd" id="bt_tree"]
```

### 4.5 ActionLeaf 标准模板

```gdscript
class_name MySkillAction extends ActionLeaf

@export var cooldown: float = 3.0
@export var animation_name: StringName = &"skill_name"
@export var animation_duration: float = 0.8
@export var damage: int = 1
@export var hitbox_on_time: float = 0.3
@export var hitbox_off_time: float = 0.5

const COOLDOWN_KEY = "cooldown_my_skill"

var _elapsed: float = 0.0
var _hitbox_active: bool = false

func tick(actor: Node, blackboard: Blackboard) -> int:
    var actor_id := str(actor.get_instance_id())

    # 冷却检查
    if Time.get_ticks_msec() < blackboard.get_value(COOLDOWN_KEY, 0.0, actor_id):
        return FAILURE

    _elapsed += actor.get_physics_process_delta_time()

    # Hitbox 窗口管理
    if _elapsed >= hitbox_on_time and _elapsed < hitbox_off_time and not _hitbox_active:
        _hitbox_active = true
        _enable_hitbox(actor, true)
    elif _elapsed >= hitbox_off_time and _hitbox_active:
        _hitbox_active = false
        _enable_hitbox(actor, false)

    # 动画完成
    if _elapsed >= animation_duration:
        _hitbox_active = false
        _enable_hitbox(actor, false)
        # 设置冷却
        blackboard.set_value(COOLDOWN_KEY, Time.get_ticks_msec() + cooldown * 1000, actor_id)
        return SUCCESS

    return RUNNING

func before_run(actor: Node, blackboard: Blackboard) -> void:
    _elapsed = 0.0
    _hitbox_active = false
    # 播放动画
    _play_animation(actor, animation_name)

func interrupt(actor: Node, blackboard: Blackboard) -> void:
    # 不清除冷却！
    if _hitbox_active:
        _hitbox_active = false
        _enable_hitbox(actor, false)
    super(actor, blackboard)

func _play_animation(actor: Node, anim: StringName) -> void:
    # 根据项目的Spine驱动实现
    pass

func _enable_hitbox(actor: Node, on: bool) -> void:
    # 开启/关闭对应的碰撞区域
    pass
```

### 4.6 ConditionLeaf 标准模板

```gdscript
class_name IsPlayerInRangeCondition extends ConditionLeaf

@export var range_distance: float = 80.0
@export var check_x_only: bool = true

func tick(actor: Node, blackboard: Blackboard) -> int:
    var players = actor.get_tree().get_nodes_in_group("player")
    if players.is_empty():
        return FAILURE
    var player = players[0]

    var dist: float
    if check_x_only:
        dist = abs(player.global_position.x - actor.global_position.x)
    else:
        dist = actor.global_position.distance_to(player.global_position)

    if dist <= range_distance:
        # 顺手更新blackboard，供后续ActionLeaf使用
        blackboard.set_value("player", player)
        blackboard.set_value("player_distance_x",
            abs(player.global_position.x - actor.global_position.x))
        return SUCCESS
    return FAILURE
```

### 4.7 apply_hit 重写模板（Boss 防御模式）

```gdscript
## Boss主脚本中重写apply_hit
func apply_hit(hit: HitData) -> bool:
    if hit == null:
        return false
    if not has_hp or hp <= 0:
        return false

    match defense_mode:
        DefenseMode.INVULNERABLE:
            return false  # 完全无敌

        DefenseMode.ARMOR:
            if not (hit.flags & HitData.Flags.PIERCE):
                _flash_once()  # 视觉反馈但0伤害
                return false
            # PIERCE武器（鬼拳）可穿透
            return _apply_damage(hit)

        DefenseMode.GUARD:
            if hit.weapon_id == &"ghost_fist":
                # 鬼拳穿透格挡
                _guard_hit_count += 1
                if _guard_hit_count >= guard_break_threshold:
                    _break_guard()
                return _apply_damage(hit)
            else:
                # 其他武器被弹开
                _play_deflect()
                return false

        DefenseMode.SUPER_ARMOR:
            # 受伤但不被打断
            var result = _apply_damage(hit)
            # 不施加硬直/击退
            return result

        _:  # NORMAL
            return _apply_damage(hit)

func _apply_damage(hit: HitData) -> bool:
    if hp_locked:
        _flash_once()
        return true
    hp = max(hp - hit.damage, 0)
    _flash_once()
    if hit.flags & HitData.Flags.STAGGER and not is_stunned():
        apply_stun(hit_stun_time, false)
    _update_weak_state()
    _check_phase_transition()
    if hp <= 0 and not hp_locked:
        _on_death()
    return true
```

---

## 五、完整示例：一个中等复杂度的 Monster

以下是一个可以直接交给 AI 的完整规范示例。

```yaml
# ============================================
# 敌人行为规范 - 暗影骑士 (ShadowKnight)
# ============================================

entity_name: "ShadowKnight"
class_name: "MonsterShadowKnight"
base_class: "MonsterBase"
entity_type: "MONSTER"
species_id: "shadow_knight"
attribute_type: "DARK"
size_tier: "MEDIUM"

max_hp: 8
weak_hp: 2
vanish_fusion_required: 2

move_type: "GROUND"
move_speed: 120.0
gravity: 1200.0

# --- 无阶段（普通怪物） ---
phases: []

# --- 技能 ---
skills:
  - id: "skill_sword_strike"
    name: "剑击"
    type: "ATTACK"
    priority: 1
    available_phases: []

    conditions:
      - type: "RANGE"
        param: "melee"
        value: 70.0
        check_axis: "X_ONLY"
      - type: "COOLDOWN"
        value: 2.5

    damage:
      amount: 2
      flags: ["KNOCKBACK"]
      weapon_id: "shadow_sword"
      hit_count: 1

    animation:
      name: "sword_strike"
      track: 0
      duration: 0.6
      loop: false
      play_mode: "FULLBODY_EXCLUSIVE"
      events:
        - { time: 0.0,  type: "ANIM_START" }
        - { time: 0.25, type: "HITBOX_ON", hitbox_id: "sword_hitbox" }
        - { time: 0.4,  type: "HITBOX_OFF" }
        - { time: 0.6,  type: "ANIM_END" }

    interruptibility:
      by_stagger: true
      by_knockback: true
      by_chain_hit: true
      by_phase_change: false
      during_windup: true
      during_active: false
      during_recovery: true

    beehave_hint:
      node_type: "ActionLeaf"
      cooldown_method: "SELF_MANAGED"
      returns_running: true
      running_frames: "duration"
      failure_on_interrupt: true

    movement_during_skill:
      type: "DASH_FORWARD"
      distance: 30.0
      speed: 200.0

    special_effects:
      - { type: "VFX", at_event: "HITBOX_ON", vfx_scene: "res://vfx/shadow_slash.tscn" }

  - id: "behavior_chase"
    name: "追击玩家"
    type: "MOVEMENT"
    priority: 5
    available_phases: []
    conditions:
      - { type: "PLAYER_DETECTED", detection_range: 300.0 }
    damage: null
    animation:
      name: "run"
      track: 0
      duration: -1
      loop: true
      play_mode: "FULLBODY_EXCLUSIVE"
    interruptibility:
      by_stagger: true
      by_knockback: true
      by_chain_hit: true
      by_phase_change: false
      during_active: true
    beehave_hint:
      node_type: "ActionLeaf"
      cooldown_method: "NONE"
      returns_running: true
      running_frames: "always"
    movement_during_skill:
      type: "MOVE_TO_PLAYER"
      speed: 120.0
      stop_distance: 60.0
      check_axis: "X_ONLY"

  - id: "behavior_patrol"
    name: "巡逻"
    type: "MOVEMENT"
    priority: 99
    available_phases: []
    conditions: []
    damage: null
    animation: { name: "walk", track: 0, duration: -1, loop: true }
    beehave_hint:
      node_type: "ActionLeaf"
      cooldown_method: "NONE"
      returns_running: true
      running_frames: "always"
    movement_during_skill:
      type: "PATROL"
      speed: 70.0
      patrol_type: "WALL_BOUNCE"

# --- 受击反应 ---
hit_reactions:
  chain_hit:
    normal_state: { damage: 1, reaction: "FLASH", can_link: false }
    weak_state: { damage: 0, reaction: "FLASH", can_link: true }
  ghost_fist_hit:
    normal_state: { damage: 1, reaction: "STAGGER", stagger_time: 0.1 }
    weak_state: { damage: 0, reaction: "STAGGER", stagger_time: 0.1 }

# --- Blackboard ---
blackboard_keys:
  player: { type: "Node2D", written_by: "ConditionLeaf" }
  cooldown_sword_strike: { type: "float", written_by: "SwordStrikeAction" }

# --- 行为树结构 ---
# SelectorReactiveComposite
# ├── SequenceReactiveComposite [MeleeSeq]
# │   ├── IsPlayerInMeleeRange (70px, 自己感知)
# │   └── SwordStrikeAction (自管理冷却2.5s)
# ├── SequenceReactiveComposite [ChaseSeq]
# │   ├── IsPlayerDetected (300px)
# │   └── MoveToPlayerAction (永远RUNNING)
# └── PatrolAction (永远RUNNING)
```

---

## 六、文档版本与更新记录

| 版本 | 日期 | 变更 |
|------|------|------|
| 1.0 | 2026-02-27 | 初始版本，包含模板和完整示例 |

---

*配套文档：*
- *`BEEHAVE_REFERENCE.md` — Beehave 2.9.x 完整 API 参考*
- *`docs/detail/ENTITY_SYSTEM.md` — 实体系统详细设计*
- *`docs/detail/WEAPON_SYSTEM.md` — 武器系统详细设计*
- *`combat/hit_data.gd` — HitData 伤害数据结构*
