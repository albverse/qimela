# BOSS_GHOST_WITCH_BLUEPRINT.md

> Phase 1 & Phase 2 蓝图修订（含 TombstoneDrop 多段动画 + 兜底移动触发说明）。

## §6 导出参数（TombstoneDrop）

```gdscript
@export var tombstone_offset_y: float = 400.0       # 墓碑出现在玩家头上的 Y 偏移
@export var tombstone_offset_x_range: float = 70.0  # 墓碑 X 偏移随机 ±
@export var tombstone_hover_duration: float = 0.5    # 空中悬停时间（秒）
@export var tombstone_fall_duration: float = 0.5     # 下落时间
@export var tombstone_stagger_duration: float = 1.0  # 落地僵直
```

## §7 行为树（Phase 1 / Phase 2）

### §7.1 Phase 1

```text
BeehaveTree
└── SelectorReactiveComposite [RootSelector]
    └── ...
        └── ActSlowMoveToPlayer        ← 兜底：玩家不在攻击范围内 → 缓慢向玩家移动
```

### §7.2 Phase 2

```text
SelectorReactiveComposite [P2Selector]
└── ...
└── ActMoveTowardPlayer                               ← 兜底：玩家不在攻击范围内 / 技能冷却中 → 向玩家移动
```

### §7.3 攻击优先级总结（Phase 2）

```text
玩家距离 ≤ 100px   → 镰刀斩（cd=1s）; 冷却中 → 等待
100px < 距离 ≤ 300px → 先检查亡灵气流（cd=15s）; 冷却中 → 飞天砸落
300px < 距离 ≤ 500px → 飞天砸落（cd=3s）; 冷却中 → 缓慢向玩家移动
距离 > 500px       → 幽灵拔河（cd=5s）; 冷却中 → 缓慢向玩家移动
所有技能冷却中     → 释放自爆幽灵 / 缓慢向玩家移动
任何时候玩家超出全部攻击检测范围 → 缓慢向玩家移动（SelectorReactive 自然落到末位兜底分支）
```

## §8.3 ActTombstoneDrop（飞天砸落 — 攻击流3）

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

## §11.1 动画事件表（TombstoneDrop）

| 动画 | 事件名 | 触发时机 | 用途 |
|---|---|---|---|
| `phase2/tombstone_cast` | `tombstone_ready` | 动画末尾 | 施法完毕，准备瞬移 |
| `phase2/tombstone_appear` | `appear_done` | 动画末尾 | 渐显完毕，进入悬停 |
| `phase2/tombstone_hover` | — | 循环 | 空中悬停 |
| `phase2/tombstone_throw` | `fall_start` | 投掷发力帧 | 幽灵向下投掷，准备下落 |
| `phase2/tombstone_fall` | — | 循环 | 高速下落中 |
| `phase2/tombstone_land` | `ground_hitbox_on` | 撞地瞬间 | 开启落地范围伤害 |
| `phase2/tombstone_land` | `ground_hitbox_off` | 冲击结束 | 关闭伤害，进入僵直 |

## 给策划的动画制作指示

飞天砸落技能需要制作 6 段动画（全部在魔女石像 SpineSprite 的 `phase2/` 文件夹下）：

1. `phase2/tombstone_cast`（false）— `tombstone_ready`
2. `phase2/tombstone_appear`（false）— `appear_done`
3. `phase2/tombstone_hover`（true）— 无
4. `phase2/tombstone_throw`（false）— `fall_start`
5. `phase2/tombstone_fall`（true）— 无
6. `phase2/tombstone_land`（false）— `ground_hitbox_on`、`ground_hitbox_off`
