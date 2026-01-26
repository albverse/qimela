# A_PHYSICS_LAYER_TABLE.md（Physics/Layer/Mask 模块，2026-01-26）

> 只在 Router 触发 B 时阅读。  
> **目的**：彻底消灭“层号 vs bitmask”的歧义。

---

## 1) 项目当前 2D Physics Layer 命名表（来自 project.godot）
| 层号(Inspector) | 层名 | bitmask | 推荐写法（必须带注释） |
|---:|---|---:|---|
| 1 | World | 1 | `1`  # World(1) / Inspector 第1层 |
| 2 | PlayerBody | 2 | `2`  # PlayerBody(2) / Inspector 第2层 |
| 3 | EnemyBody | 4 | `4`  # EnemyBody(3) / Inspector 第3层 |
| 4 | EnemyHurtbox | 8 | `8`  # EnemyHurtbox(4) / Inspector 第4层 |
| 5 | ObjectSense | 16 | `16`  # ObjectSense(5) / Inspector 第5层 |
| 6 | hazards | 32 | `32`  # hazards(6) / Inspector 第6层 |
| 7 | ChainInteract | 64 | `64`  # ChainInteract(7) / Inspector 第7层 |

---

## 2) 换算规则（写死）
- 第N层（Inspector） → bitmask = 1 << (N-1)
- bitmask 16 → 第5层（因为 16 = 1<<(5-1)）

---

## 3) 强制书写格式（必须）
任何出现碰撞层/遮罩时，必须用以下格式之一：

### 3.1 单层（推荐）
```gdscript
collision_layer = 16  # ObjectSense(5) / Inspector 第5层
collision_mask  = 16  # ObjectSense(5) / Inspector 第5层
```

### 3.2 多层（必须逐层注释）
```gdscript
# World(1)=1, EnemyBody(3)=4, ObjectSense(5)=16
collision_mask = 1 | 4 | 16  # World(1)+EnemyBody(3)+ObjectSense(5) / Inspector 第1+3+5层
```

---

## 4) 本项目 LightReceiver 的真实配置（来自 MonsterFly.tscn）
```gdscript
collision_layer = 16  # ObjectSense(5) / Inspector 第5层
collision_mask  = 16  # ObjectSense(5) / Inspector 第5层
```
