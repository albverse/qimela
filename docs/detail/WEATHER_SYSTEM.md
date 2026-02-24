# 天气系统详细说明

> 对应主表：[GAME_ARCHITECTURE_MASTER.md](../GAME_ARCHITECTURE_MASTER.md) → 模块 16

---

## 1. 概览

| 项目 | 值 |
|------|-----|
| 文件 | `systems/weather_controller.gd` |
| 类名 | `WeatherController` |
| 继承 | Node |
| 职责 | 随机间隔触发雷击，广播全局事件 |

---

## 2. 节点结构

```
WeatherController (Node)
├── ThunderTimer (Timer)       # 随机间隔计时器
├── AnimationPlayer            # 雷击动画（可选）
└── ThunderPostFX (引用)       # 屏幕闪光效果（ThunderPostFX 节点）
```

---

## 3. 雷击流程

```
_ready():
  → _schedule_next(start_delay)      # 延迟启动

ThunderTimer.timeout:
  → _start_thunder()
    → 有动画? → AnimationPlayer.play("thunder")
                → 动画中调用 anim_emit_thunder_burst()  (Call Method Track)
                → 动画结束 → _schedule_next()
    → 无动画? → _fallback_emit_then_schedule()
                → 0.2s 后 emit thunder_burst
                → _schedule_next()
```

---

## 4. 关键参数

| 参数 | 默认值 | 说明 |
|------|--------|------|
| interval_min | 0.0 | 雷击最小间隔（秒） |
| interval_max | 7.0 | 雷击最大间隔（秒） |
| start_delay | 1.0 | 场景启动后首次雷击延迟 |
| thunder_add_seconds | 3.0 | 每次雷击给怪物/雷花增加的光照秒数 |
| thunder_animation | `"thunder"` | AnimationPlayer 中的动画名 |

---

## 5. 信号发射

```gdscript
EventBus.thunder_burst.emit(thunder_add_seconds)
```

**接收者：**
- `MonsterBase._on_thunder_burst(add_seconds)` → 增加 light_counter
- `LightningFlower._on_thunder_burst(_add_seconds)` → 能量 +1

---

## 6. ThunderPostFX

- 屏幕闪光特效节点
- 使用 `shaders/thunder_post_fx.gdshader`
- 雷击时调用 `_thunder_fx.thunder_flash()`
- 快速白闪 → 淡出

---

## 7. 防重复

- `_emitted_this_cycle` 标志确保每次雷击周期只发射一次 `thunder_burst`
- 动画结束后重置
