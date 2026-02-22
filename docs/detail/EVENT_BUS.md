# 事件总线详细说明

> 对应主表：[GAME_ARCHITECTURE_MASTER.md](../GAME_ARCHITECTURE_MASTER.md) → 模块 13

---

## 1. 概览

| 项目 | 值 |
|------|-----|
| 文件 | `autoload/event_bus.gd` |
| 类型 | Autoload / Singleton |
| 访问 | 全局 `EventBus` |
| 职责 | 全局信号中心，解耦系统间通信 |

---

## 2. 信号清单

### 天气/光照信号

| 信号 | 参数 | 发射者 | 订阅者 |
|------|------|--------|--------|
| `thunder_burst` | `add_seconds: float` | WeatherController | MonsterBase, LightningFlower |
| `light_started` | `source_id: int, remaining_time: float, source_light_area: Area2D` | LightningFlower | MonsterBase, LightningFlower（连锁） |
| `light_finished` | `source_id: int` | LightningFlower | MonsterBase, LightningFlower |
| `healing_burst` | `light_energy: float` | Player（Q键） | MonsterBase, LightningFlower |

### 锁链信号

| 信号 | 参数 | 发射者 | 订阅者 |
|------|------|--------|--------|
| `slot_switched` | `active_slot: int` | ChainSystem | ChainSlotsUI |
| `chain_fired` | `slot: int` | ChainSystem | ChainSlotsUI |
| `chain_bound` | `slot: int, target: Node, attribute: int, icon_id: int, is_chimera: bool, show_anim: bool` | ChainSystem | ChainSlotsUI |
| `chain_released` | `slot: int, reason: StringName` | ChainSystem | ChainSlotsUI |
| `chain_struggle_progress` | `slot: int, t01: float` | ChainSystem | ChainSlotsUI |

### 融合信号

| 信号 | 参数 | 发射者 | 订阅者 |
|------|------|--------|--------|
| `fusion_rejected` | （无） | ChainSystem | ChainSlotsUI（震动效果） |

---

## 3. 发射方法约定

所有信号都通过 `emit_<signal_name>()` 包装方法发射：

```gdscript
# 示例
EventBus.emit_thunder_burst(3.0)
EventBus.emit_chain_fired(0)
EventBus.emit_chain_bound(slot, target, attr, icon, is_chimera, show_anim)
```

调用端通常做安全检查：
```gdscript
if EventBus != null and EventBus.has_method("emit_chain_fired"):
    EventBus.emit_chain_fired(idx)
```

---

## 4. 设计原则

1. **解耦**：系统间不持有直接引用，通过信号通信
2. **单向流**：信号发射者不关心谁在监听
3. **安全**：发射前检查 `EventBus != null` 和 `has_method`
4. **命名一致**：信号名 `snake_case`，发射方法 `emit_` 前缀
