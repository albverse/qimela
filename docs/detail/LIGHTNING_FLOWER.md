# 雷电花系统详细说明

> 对应主表：[GAME_ARCHITECTURE_MASTER.md](../GAME_ARCHITECTURE_MASTER.md) → 模块 15

---

## 1. 概览

| 项目 | 值 |
|------|-----|
| 文件 | `scene/lightning_flower.gd` |
| 场景 | `scene/LightningFlower.tscn` |
| 类名 | `LightningFlower` |
| 继承 | Node2D |
| 能量上限 | 5（ENERGY_MAX） |

---

## 2. 能量系统

### 充能来源

| 来源 | 触发 | 每次增加 |
|------|------|----------|
| 雷击 | `EventBus.thunder_burst` | +1 |
| 治愈大爆炸 | `EventBus.healing_burst` | +int(light_energy) |
| 其他花的光照 | `EventBus.light_started`（范围内） | +1（延迟 0.5s） |
| 锁链命中 | `on_chain_hit()` | 触发释放（不充能） |

### 释放条件

| 条件 | 触发方式 |
|------|----------|
| 满能量 + 雷击 | 自动释放 |
| 满能量 + 治愈大爆炸 | 自动释放 |
| 满能量 + 其他花光照 | 自动释放 |
| 锁链命中（allow_chain_release=true） | 手动触发释放 |

---

## 3. 光照释放流程

```
_release_light_with_energy(release_energy):
  1. 计算光照时间 = release_energy × light_time_per_energy
  2. 清空能量 → 0
  3. 闪光效果（PointLight2D 高亮 → 淡出）
  4. 通知范围内怪物（_notify_monsters_in_range）
  5. 释放瞬间伤害（_damage_targets_in_hurt_area）
  6. 广播 EventBus.light_started（给其他花连锁）
  7. 等待 light_time 秒
  8. 广播 EventBus.light_finished
```

---

## 4. HurtArea 伤害规则

| 目标类型 | 效果 |
|----------|------|
| Player | `apply_damage(1)` |
| MonsterFly / flying_monster 组 | **免疫**（不受伤、不眩晕） |
| MonsterWalk | **不掉血，改眩晕**（`walk_stun_time` 秒） |
| 其他怪物 | `take_damage(1)` |

---

## 5. 连锁机制

花 A 释放光照 → 花 B 在 LightArea 范围内 → 花 B 收到 `light_started` 信号：
- 延迟 `LIGHT_ENERGY_DELAY`（0.5s）后 +1 能量
- 如果花 B 已满能量 → 触发花 B 释放 → 可能触发花 C...

---

## 6. 锁链交互

```gdscript
func on_chain_hit(_player: Node, _slot: int) -> int:
    if not allow_chain_release: return 0
    if chain_release_requires_full and energy < ENERGY_MAX: return 0
    # 释放当前能量（或要求满能量）
    _release_light_with_energy(energy)
    return 1  # 锁链链接成功
```

---

## 7. 视觉状态

- 6 个能量纹理（`lightflower_0.png` ~ `lightflower_5.png`）
- `_apply_energy_texture(idx)` 根据当前能量切换纹理
- PointLight2D 亮度 = `energy × glow_energy_per_charge`
- 释放瞬间：亮度暴增 + 快速淡出

---

## 8. 关键参数

| 参数 | 默认值 | 说明 |
|------|--------|------|
| initial_energy | 0 | 初始能量 |
| light_time_per_energy | 1.0 | 每格能量的光照持续秒数 |
| allow_chain_release | true | 是否允许锁链触发释放 |
| chain_release_requires_full | false | 锁链触发是否要求满能量 |
| walk_stun_time | 2.0 | Walk 怪眩晕时间 |
| glow_energy_per_charge | 0.6 | 每格能量对应的 PointLight 亮度 |
| glow_flash_bonus | 10.0 | 释放瞬间额外亮度 |
