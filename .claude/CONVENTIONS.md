# 项目实战经验备忘（供 Claude Code 后续 session 快速回忆）

## 1. 架构概况

### 实体继承链
- `EntityBase` → `MonsterBase` → 具体怪物脚本
- Chimera 类型实体（如 ChimeraNunSnake）虽然 `entity_type = CHIMERA`，但继承 `MonsterBase`（不是 ChimeraBase）
- 链条规则走 Monster 逻辑：默认不可链，只有 weak/stunned 状态可链

### 玩家（Player）
- `scene/player.gd` — CharacterBody2D，调度总线
- tick 顺序: Movement → move_and_slide → LocomotionFSM → ChainSystem → ActionFSM → Animator
- 有 `debug_invincible: bool` 测试开关（跳过 apply_damage）
- 有 PETRIFIED 石化状态（apply_petrify / is_petrified / execute_petrified_death）
- 伤害入口: `apply_damage(amount, source_global_pos)` → health 组件
- 僵直入口: `apply_stun(seconds)` → ActionFSM Hurt 状态

### 动画驱动
- `AnimDriverSpine` (`scene/components/anim_driver_spine.gd`) — Spine 官方动画驱动
  - API 签名自动检测: (track,name,loop) 或 (name,loop,track)
  - 信号 + 轮询双保险检测动画完成
  - `play(track, anim_name, loop, PlayMode)` — PlayMode: OVERLAY / EXCLUSIVE / REPLACE_TRACK
  - `anim_completed(track, anim_name)` 信号
  - 骨骼坐标: `get_bone_world_position(bone_name)`
- `AnimDriverMock` (`scene/components/anim_driver_mock.gd`) — 无 Spine 时的占位驱动
  - 手写时长表 `_durations`，loop=true 永不完成，loop=false 倒计时后触发 anim_completed
  - 不会触发 Spine events（atk_hit_on/off, eye_hurtbox_enable 等）

### Beehave 行为树
- 插件版本: 2.9.x
- .tscn 格式: `type="Node"` + `script=ExtResource`（不用 `type="BeehaveTree"`）
- `SelectorReactiveComposite` — 每帧从头重评估，优先级高的分支可抢占
- `SequenceReactiveComposite` — 每帧重评估条件，正在运行的 action 不重新 before_run
- BT 由 BeehaveTree 自身 `_physics_process` 驱动 tick
- **关键**: 父节点 `_physics_process` 先于子节点执行（标准 Godot 树序）

## 2. 已实现怪物

### StoneEyeBug（石眼虫）
- `scene/enemies/stone_eyebug/`
- 两种形态: 壳体 (StoneEyeBug) + 软体 (Mollusc)
- 重力 800 px/s²，在 BT action 中施加（不在主脚本 _physics_process）
- Beehave 驱动 AI

### StoneMaskBird（石面鸟）
- `scene/enemies/stone_mask_bird/`
- 飞行怪，fall_gravity 600 px/s²
- `_do_move()` 为空（飞行，不走 MonsterBase 移动）

### ChimeraNunSnake（修女蛇）— 最新实现
- `scene/enemies/chimera_nun_snake/`
- 5 顶层状态: CLOSED_EYE(0) / OPEN_EYE(1) / GUARD_BREAK(2) / WEAK(3) / STUN(4)
- 重力 1200 px/s²（与 MonsterWalk 同步），在 `_physics_process` 中统一施加
- **不调用 `super._physics_process()`** — weak/stun 计时器自行管理
- 攻击冷却: `@export attack_cooldown_sec = 1.0`

#### BT 结构（优先级从高到低）
```
RootSelector (SelectorReactive)
├─ Seq_WeakOrStun [Cond_IsWeakOrStun, Act_HandleWeakOrStun]
├─ Seq_PetrifiedChase [Cond_HasPetrifiedTarget, Act_PetrifiedChase]
├─ Seq_GuardBreak [Cond_ModeGuardBreak(2), Act_GuardBreakFlow]
├─ Seq_OpenEyeAttack [Cond_ModeOpenEye(1), Act_OpenEyeAttackChain]
├─ Seq_ClosedEyeReact [Cond_ModeClosedEye(0), Cond_DetectTarget, Act_ClosedEyeIntent]
└─ Act_ClosedEyeIdle（兜底）
```

#### OPEN_EYE 固定攻击链
`close_to_open → stiff_attack → open_eye_idle → shoot_eye_start → shoot_eye_loop → shoot_eye_end → open_eye_to_close`

#### 攻击选择逻辑
- h_dist <= stiff_attack_range(80) → 设 mode=OPEN_EYE, SUCCESS → 下帧 OpenEyeAttackChain 接管
- h_dist <= ground_pound_range(110) → 闭眼 ground_pound
- 攻击后有冷却期（COOLDOWN_WALK），冷却中继续行走接近

#### 眼球子弹
- `nun_snake_eye_projectile.gd` — Area2D, Phase: OUTBOUND → HOVER → RETARGET(3次) → RETURNING
- 命中玩家调 `apply_petrify()`, 不销毁, 返航
- `force_recall()` 由 WEAK/STUN 触发

#### 受击规则
- CLOSED_EYE: 破防来源(ghost_fist等) → GUARD_BREAK，普通攻击 → hit_resist 动画
- OPEN_EYE/GUARD_BREAK: 仅 EyeHurtbox 有效，主体无效
- WEAK/STUN: hp_locked，只闪白，可链接

## 3. 踩坑记录

### 物理查询刷新错误
- `_set_hitbox_enabled` / `_set_eye_hurtbox_enabled` 中的 monitoring/monitorable/disabled
- 在 area_entered 信号回调链中修改会触发 "Can't change this state while flushing queries"
- **必须用 `set_deferred()`**: `hitbox.set_deferred("monitoring", value)`, `cs.set_deferred("disabled", value)`

### 重力浮空问题
- BT action 的 `velocity = Vector2.ZERO` 会清除 velocity.y，导致重力无法帧间累积
- **只清 velocity.x**: `snake.velocity.x = 0.0`
- 重力在 `_physics_process` 统一施加 + `move_and_slide()`

### BT SelectorReactive 与状态切换
- SelectorReactive 每帧从头检查所有分支的 Condition
- 从 ClosedEyeIntent 切到 OpenEyeAttackChain 需要:
  1. ClosedEyeIntent 设 `snake.mode = Mode.OPEN_EYE`
  2. 返回 SUCCESS
  3. 下一帧 SelectorReactive 从头评估，Cond_ModeOpenEye 通过
  4. OpenEyeAttackChain.before_run() 播放 close_to_open

### 攻击范围死循环
- 如果 ground_pound_range > stiff_attack_range 且无冷却，怪物永远在 ground_pound_range 反复锤地
- **必须加冷却** + 冷却中继续行走，才能走进 stiff_attack_range

## 4. 重力常数参考

| 实体 | 重力 (px/s²) |
|------|-------------|
| Player | 1500 |
| MonsterWalk / MonsterNeutral | 1200 |
| StoneEyeBug / Mollusc | 800 |
| StoneMaskBird (下落) | 600 |
| ChimeraNunSnake | 1200 |

## 5. 碰撞层速查

| 层号 | 名称 | bitmask |
|------|------|---------|
| 1 | World | 1 |
| 2 | PlayerBody | 2 |
| 3 | EnemyBody | 4 |
| 4 | EnemyHurtbox | 8 |
| 5 | ObjectSense | 16 |
| 6 | Hazards | 32 |
| 7 | ChainInteract | 64 |

公式: 第 N 层 → bitmask = `1 << (N-1)`

## 6. 文件命名规范
- `.tscn` → PascalCase (ChimeraNunSnake.tscn)
- `.gd` → snake_case (chimera_nun_snake.gd)
- `class_name` → PascalCase (ChimeraNunSnake)
- Beehave condition: `cond_*.gd` + `Cond*` class
- Beehave action: `act_*.gd` + `Act*` class
- BT 场景: `bt_*.tscn`

## 7. 关键 API 模式

### 怪物动画播放（NunSnake 模式）
```gdscript
snake.anim_play(&"anim_name", loop_bool)
snake.anim_is_playing(&"anim_name")  # → bool
snake.anim_is_finished(&"anim_name")  # → bool
```

### Spine 事件处理
```gdscript
func _on_spine_animation_event(a1, a2, a3, a4) -> void:
    # 遍历参数找到 SpineEvent 对象
    # event.get_data().get_event_name() 获取事件名
```

### EventBus
- 只用 `emit_*()` 包装方法，不直接 `.emit()`
- 全局单例: `autoload/event_bus.gd`

### HitData 伤害传递
- `apply_hit(hit: HitData) -> bool`
- `hit.weapon_id` 判定破防/眩晕来源
- `hit.damage` 伤害值
