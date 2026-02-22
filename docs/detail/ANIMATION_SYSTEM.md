# 动画系统详细说明

> 对应主表：[GAME_ARCHITECTURE_MASTER.md](../GAME_ARCHITECTURE_MASTER.md) → 模块 7

---

## 1. 架构概览

| 项目 | 值 |
|------|-----|
| 裁决器 | `PlayerAnimator` (`scene/components/player_animator.gd`) |
| 驱动模式 | `MOCK`（AnimDriverMock）或 `SPINE`（AnimDriverSpine） |
| 轨道数 | 2 — Track0=移动层, Track1=动作覆盖层 |

**核心原则：PlayerAnimator 是唯一的动画播放权威。** 任何组件（FSM/Chain/Weapon）都不直接播放动画，只通过 Animator 接口。

---

## 2. 双轨道系统

### Track0（移动层 / Locomotion）
- 始终跟随 `LocomotionFSM.state` → 映射到对应动画名
- 由 `Animator.tick(dt)` 每帧自动裁决
- 永远不会被 Action 动画"清除"（除非 FULLBODY_EXCLUSIVE 模式）

### Track1（动作覆盖层 / Action Overlay）
- 由 ActionFSM 状态变化触发
- 覆盖 Track0 的上半身动画（OVERLAY 模式）
- 动画结束后清空 Track1，Track0 继续

### 三种播放模式

| 模式 | 枚举值 | 行为 | 使用场景 |
|------|--------|------|----------|
| OVERLAY_UPPER | 0 | Track1 覆盖上半身，Track0 持续播放 | Chain 发射 |
| OVERLAY_CONTEXT | 1 | Track1 覆盖，根据上下文选择动画 | Sword/Knife 攻击 |
| FULLBODY_EXCLUSIVE | 2 | 清空所有轨道，在 Track0 播放 | Fuse, Die |

---

## 3. 动画名映射

### LOCO_ANIM（移动状态 → 动画名）

| 状态 | 动画名 |
|------|--------|
| Idle | `idle` |
| Walk | `walk` |
| Run | `run` |
| Jump_up | `jump_up` |
| Jump_loop | `jump_loop` |
| Jump_down | `jump_down` |
| Dead | `die` |

### ACTION_ANIM（动作状态 → 动画名）

| 动作 | 动画名 |
|------|--------|
| Chain_R | `chain_R` |
| Chain_L | `chain_L` |
| Chain_cancel_R | `chain_cancel_R` |
| Chain_cancel_L | `chain_cancel_L` |
| Hurt | `hurt` |
| Die | `die` |
| Fuse | `fuse` |
| Sword 攻击 | 由 WeaponController 返回上下文动画名 |
| Knife 攻击 | 由 WeaponController 返回上下文动画名 |

---

## 4. 上下文计算（_compute_context）

```gdscript
func _compute_context() -> String:
    if not player.is_on_floor():
        return "air"
    var intent: int = player.movement.move_intent
    if intent == 0:  # NONE
        return "ground_idle"
    return "ground_move"  # WALK or RUN
```

上下文决定 Sword/Knife 攻击使用哪个具体动画。

---

## 5. Chain 动画的特殊处理

Chain 动画不走标准 ActionFSM → Animator 路径，而是通过手动触发：

### 发射动画
```
ChainSystem._play_chain_fire_anim(slot)
  → Animator.play_chain_fire(slot)
    → 设置 _manual_chain_anim = true
    → 播放 "chain_R" 或 "chain_L" 在 Track1
```

### 取消动画
```
player._unhandled_input (X键)
  → Animator.play_chain_cancel(right_active, left_active)
    → 播放 "chain_cancel_R/L"
```

### _manual_chain_anim 标志
- 当此标志为 true 时，Animator.tick() 不会清除 Track1 上的 Chain 动画
- 防止正常 tick 裁决覆盖手动触发的 Chain 动画
- 动画结束后自动重置

---

## 6. 驱动系统

### AnimDriverMock（开发/测试用）
- 使用标准 AnimationPlayer
- 不需要 Spine 资源
- 默认驱动，总是可用

### AnimDriverSpine（正式用）
- 使用 Spine 2D 运行时
- 从 `art/player/spine/` 加载骨骼数据
- 支持骨骼锚点获取
- 动态加载，找不到则回退到 Mock

### Chain 锚点桥接
```gdscript
func get_chain_anchor_position(use_right_hand: bool) -> Vector2:
    # Spine 模式：从骨骼 "chain_anchor_r" / "chain_anchor_l" 获取位置
    # Mock 模式：从 Marker2D HandR/HandL 获取位置
    # 兜底：返回 player.global_position
```

---

## 7. Facing 翻转

```gdscript
# Visual.scale.x = facing * facing_visual_sign
# facing = 1 (右) 或 -1 (左)
# facing_visual_sign 默认 -1.0（根据美术资源朝向调整）
```

每帧在 Animator.tick() 末尾更新，确保视觉朝向与逻辑朝向一致。

---

## 8. 相关文档

- 动画规范包详细文档：`docs/AI_Animation_Spec_Pack_/`
- Spine 资源要求：`docs/AI_Animation_Spec_Pack_/05_SPINE_ASSET_REQUIREMENTS.md`
- 武器动画 Profile 规范：`docs/AI_Animation_Spec_Pack_/11_WEAPON_ANIM_PROFILE_SPEC.md`（未来计划，未实现）
