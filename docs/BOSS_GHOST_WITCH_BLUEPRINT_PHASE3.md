# BOSS_GHOST_WITCH_BLUEPRINT_PHASE3.md

> Phase 3（无头骑士）修订补丁：召唤幽灵（ActSummonGhosts）技能重做。

## P3-3.1 攻击优先级总结（节选）

```text
优先级 3：召唤幽灵
  → 玩家在跳板上 + ≤500px + 镰刀在手
  → 起手施法动画自带 combo3 攻击判定（一边召唤一边顺手砍一刀）
  → 地面出现圆圈 → 0.3s 后幽灵飞出 → 5秒内3波
  → 施法全程不可移动，维持 summon_loop 直到场上所有召唤幽灵被销毁才结束
```

## P3-5.8 ActSummonGhosts（召唤幽灵 — 施法含 combo3 攻击）

```gdscript
## 施法起手（含 combo3 攻击判定）→ 生成幽灵波次 → summon_loop 维持 → 等所有 GhostSummon 销毁 → 结束
## 全程不可移动
class_name ActSummonGhosts extends ActionLeaf

enum Step {
    CAST,           # 播放 summon 起手（内含 combo3 攻击判定）+ 生成幽灵
    SUMMON_LOOP,    # summon_loop 循环，等待场上所有 GhostSummon 被销毁
    DONE
}

var _step: int = Step.CAST
var _wave_index: int = 0
var _wave_timer: float = 0.0
var _wave_interval: float = 0.0
var _cast_done: bool = false  # summon 起手是否播完

func before_run(actor: Node, _bb: Blackboard) -> void:
    _step = Step.CAST
    _wave_index = 0
    _wave_timer = 0.0
    _cast_done = false

func tick(actor: Node, blackboard: Blackboard) -> int:
    var boss := actor as BossGhostWitch
    if boss == null: return FAILURE
    var dt := get_physics_process_delta_time()

    # 全程锁定移动
    actor.velocity.x = 0.0

    match _step:
        Step.CAST:
            if not _cast_done:
                boss.anim_play(&"phase3/summon", false)
                _wave_interval = 5.0 / float(boss.p3_summon_wave_count)
                # Spine 事件 "combo3_hitbox_on" / "combo3_hitbox_off" 在 summon 动画中触发
                # Spine 事件 "circle_spawn" 在 summon 动画中触发第一波

            # 施法动画播放期间也推进波次计时
            _wave_timer += dt
            var expected_waves := int(_wave_timer / _wave_interval)
            if expected_waves > _wave_index and _wave_index < boss.p3_summon_wave_count:
                _spawn_wave(boss)
                _wave_index += 1

            # 起手动画播完
            if boss.anim_is_finished(&"phase3/summon"):
                _cast_done = true
                _step = Step.SUMMON_LOOP
            return RUNNING

        Step.SUMMON_LOOP:
            boss.anim_play(&"phase3/summon_loop", true)

            # 继续推进剩余波次（如果起手动画播完时波次还没全部生成）
            if _wave_index < boss.p3_summon_wave_count:
                _wave_timer += dt
                var expected_waves := int(_wave_timer / _wave_interval)
                if expected_waves > _wave_index:
                    _spawn_wave(boss)
                    _wave_index += 1

            # 等待场上所有 GhostSummon 被销毁
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

    # 位置：1个玩家位置 + 2个随机地面位置
    var positions: Array[Vector2] = []
    positions.append(player.global_position)
    for i in range(boss.p3_summon_circle_count - 1):
        var random_x := player.global_position.x + randf_range(-300, 300)
        positions.append(Vector2(random_x, player.global_position.y))

    for pos in positions:
        var summon: Node2D = boss._ghost_summon_scene.instantiate()
        summon.add_to_group("ghost_summon")
        if summon.has_method("setup"):
            summon.call("setup", 0.3)  # 0.3s 后幽灵飞出
        summon.global_position = pos
        boss.get_parent().add_child(summon)

func _set_cooldown(actor: Node, bb: Blackboard, key: String, cd: float) -> void:
    bb.set_value(key, Time.get_ticks_msec() + cd * 1000.0, str(actor.get_instance_id()))

func interrupt(actor: Node, blackboard: Blackboard) -> void:
    _step = Step.CAST
    _cast_done = false
    # 关闭 combo3 hitbox（防止残留）
    var boss := actor as BossGhostWitch
    if boss: boss._close_all_combo_hitboxes()
    super(actor, blackboard)
```

## P3-8 动画表（召唤段）

| 动画 | 说明 | loop | 事件 |
|---|---|---|---|
| `phase3/summon` | 召唤起手（含 combo3 攻击） | false | `combo3_hitbox_on`、`combo3_hitbox_off`、`circle_spawn` |
| `phase3/summon_loop` | 维持施法姿态，等待幽灵被销毁 | true | — |

## P3-9 攻击参数总表（召唤行）

| 攻击名 | 触发条件 | 范围(px) | 冷却(s) | 伤害 | 可打断 | 优先级 |
|---|---|---:|---:|---|---|---:|
| 召唤幽灵 | 玩家在跳板+≤500px+镰刀在手 | 500 | 8(待定) | 1(碰撞) + 起手附带combo3攻击 | 否，全程锁定不可移动 | 3 |

## 给策划的动画指示

召唤幽灵技能需要修改为 2 段动画：

| 动画名 | loop | 描述 | 事件 |
|---|---|---|---|
| `phase3/summon` | false | 施法起手，Boss 挥动镰刀召唤的同时顺带做一次 combo3 的攻击动作 | `combo3_hitbox_on`（攻击判定开启）、`combo3_hitbox_off`（攻击判定关闭）、`circle_spawn`（召唤圆圈出现） |
| `phase3/summon_loop` | true | 维持施法姿态，Boss 保持召唤的站姿不动，等待召唤出的幽灵全部消失 | 无 |

播放顺序：`phase3/summon`（起手+攻击）→ `phase3/summon_loop`（循环等待）→ 幽灵全部销毁 → 结束。

注意：`phase3/summon` 中的 combo3 攻击判定复用 Attack3Area 的 hitbox，事件名与 `phase3/combo3` 中一致（`combo3_hitbox_on` / `combo3_hitbox_off`），方便代码侧统一处理。
