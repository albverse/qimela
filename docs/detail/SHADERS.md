# Shader 特效详细说明

> 对应主表：[GAME_ARCHITECTURE_MASTER.md](../GAME_ARCHITECTURE_MASTER.md) → 模块 18

---

## 1. Shader 清单

| 文件 | 用途 | 使用者 |
|------|------|--------|
| `chain_sand_dissolve.gdshader` | 锁链溶解效果 | PlayerChainSystem |
| `chain_cooldown_fill.gdshader` | 槽位冷却填充 | ChainSlotsUI |
| `fire_Burn_shader.gdshader` | 怪物图标燃烧消失 | ChainSlotsUI |
| `thunder_post_fx.gdshader` | 雷击屏幕闪光 | ThunderPostFX |
| `burn_dissolve.gdshader` | 通用燃烧溶解 | （备用） |

---

## 2. chain_sand_dissolve.gdshader

**用途：** 锁链的 Line2D 从实体到消失的沙化溶解效果。

| 参数 | 类型 | 范围 | 说明 |
|------|------|------|------|
| `burn` | float | 0.0 → 1.0 | 溶解进度（0=完整，1=完全消失） |

**使用位置：** `player_chain_system.gd` → `_begin_burn_dissolve()` → Tween 驱动 `burn` 参数

```gdscript
c.line.material = c.burn_mat
c.burn_mat.set_shader_parameter("burn", 0.0)
# Tween: burn 从 0.0 → 1.0，持续 burn_time 秒
```

---

## 3. chain_cooldown_fill.gdshader

**用途：** 锁链槽位图标的冷却填充效果（从空到满）。

| 参数 | 类型 | 范围 | 说明 |
|------|------|------|------|
| `progress` | float | 0.0 → 1.0 | 填充进度（0=空，1=满/可用） |

**使用位置：** `chain_slots_ui.gd` → `_start_cooldown()` → Tween 驱动 `progress`

---

## 4. fire_Burn_shader.gdshader

**用途：** UI 上怪物图标的火焰燃烧消失效果。

| 参数 | 类型 | 说明 |
|------|------|------|
| `noise` | Texture2D | 噪声纹理（FastNoiseLite 生成） |
| `colorCurve` | Texture2D | 颜色曲线（Gradient：黑→橙→白） |
| `progress` | float | 燃烧进度（0.0 → 2.0） |
| `timed` | bool | 是否自动计时（UI 中设为 false，手动驱动） |

**使用位置：** `chain_slots_ui.gd` → `_setup_burn_shader_on_icon()` + `_update_burn_progress()`

噪声和颜色曲线在 `_setup_burn_assets()` 中程序化生成：
```gdscript
# 噪声：SimplexNoise, freq=6.0, 128×128
# 颜色曲线：黑(0) → 橙红(0.2) → 亮橙(0.6) → 白透明(1.0)
```

---

## 5. thunder_post_fx.gdshader

**用途：** 雷击时的全屏闪光效果。

由 `scene/thunder_post_fx.gd` (`ThunderPostFX` 类) 控制：
- `thunder_flash()` 触发闪光
- 快速白闪 → 淡出

---

## 6. burn_dissolve.gdshader

**用途：** 通用燃烧溶解效果（备用/其他实体可用）。

与 `chain_sand_dissolve` 类似但视觉风格不同。
