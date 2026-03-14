# BOSS_GHOST_WITCH_BLUEPRINT.md

## §6 导出参数（TombstoneDrop）

```gdscript
@export var tombstone_offset_y: float = 400.0       # 墓碑出现在玩家头上的 Y 偏移
@export var tombstone_offset_x_range: float = 70.0  # 墓碑 X 偏移随机 ±
@export var tombstone_hover_duration: float = 0.5   # 空中悬停时间（秒）
@export var tombstone_fall_duration: float = 0.5    # 下落时间
@export var tombstone_stagger_duration: float = 1.0 # 落地僵直
```

## §8.3 ActTombstoneDrop（飞天砸落 — 攻击流3）

- 状态机改为 8 段：
  1. CAST
  2. TELEPORT
  3. APPEAR
  4. HOVER
  5. THROW
  6. FALLING
  7. LAND
  8. STAGGER

- 播放顺序：
  `phase2/tombstone_cast` → 瞬移 → `phase2/tombstone_appear` → `phase2/tombstone_hover`（短循环）
  → `phase2/tombstone_throw` → `phase2/tombstone_fall`（循环至落地）
  → `phase2/tombstone_land`。

## §11.1 动画事件表（TombstoneDrop）

| 动画 | 事件名 | 时机 | 用途 |
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

1. `phase2/tombstone_cast`（false）— 事件：`tombstone_ready`
2. `phase2/tombstone_appear`（false）— 事件：`appear_done`
3. `phase2/tombstone_hover`（true）— 无
4. `phase2/tombstone_throw`（false）— 事件：`fall_start`
5. `phase2/tombstone_fall`（true）— 无
6. `phase2/tombstone_land`（false）— 事件：`ground_hitbox_on`、`ground_hitbox_off`
