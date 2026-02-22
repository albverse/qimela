# 治愈精灵详细说明

> 对应主表：[GAME_ARCHITECTURE_MASTER.md](../GAME_ARCHITECTURE_MASTER.md) → 模块 17

---

## 1. 概览

| 项目 | 值 |
|------|-----|
| 文件 | `scene/healing_sprite.gd` |
| 场景 | `scene/HealingSprite.tscn` |
| 类名 | `HealingSprite` |
| 继承 | Node2D |

---

## 2. 状态机

```
IDLE_IN_WORLD → ACQUIRE → ORBIT → VANISH → CONSUMED
       ↑                    ↓
       └── 死亡清理 ←───────┘
```

| 状态 | 说明 |
|------|------|
| IDLE_IN_WORLD | 在世界中等待被拾取 |
| ACQUIRE | 飞向玩家的过渡动画 |
| ORBIT | 围绕玩家椭圆轨道运行 |
| VANISH | 消耗/消失过渡 |
| CONSUMED | 最终清理 |

---

## 3. 拾取方式

| 方式 | 触发条件 |
|------|----------|
| 自动拾取 | 玩家进入 `acquire_range`（默认 150px）范围 |
| 锁链命中 | `on_chain_hit()` 返回 1，立即进入 ACQUIRE |

拾取时调用 `Player.try_collect_healing_sprite(self)` 获取槽位。

---

## 4. 轨道运动

### 椭圆轨道
- 围绕 `Player.get_healing_orbit_center_global(index)` 运行
- center1 / center2 / center3 对应三个槽位的轨道中心
- 水平半径 / 垂直半径可配置

### 伪 3D 缩放
- 根据轨道 Y 轴位置调整 `scale`
- 在前方（Y 较大）时放大，后方缩小
- 产生围绕角色旋转的深度感

### 跳跃滞后
- 垂直位置使用 0.3s 平滑跟随（smoothed Y）
- 玩家跳跃时精灵会"拖尾"
- 增强自然感

### 个体差异
- 速度倍率：每个精灵有随机 speed_mult
- 摆动：随机 wobble 幅度
- 轨道方向：部分精灵反向旋转
- 两个精灵同在时相位分离（避免重叠）

---

## 5. 使用方式

### C 键 — 消耗单个精灵
```
Player.use_healing_sprite():
  → 找到第一个有效精灵
  → 清空槽位
  → sprite.consume()
  → Player.heal(healing_per_sprite)  # 默认 2 HP
```

### Q 键 — 治愈大爆炸
```
Player.use_healing_burst():
  前提：所有 3 个槽位都有精灵
  → 消耗所有精灵
  → 给予玩家短暂无敌（healing_burst_invincible_time）
  → 范围内怪物眩晕（MonsterBase.apply_healing_burst_stun）
  → 发射全场光照能量（EventBus.healing_burst）
```

---

## 6. 玩家侧参数

| 参数 | 默认值 | 说明 |
|------|--------|------|
| max_healing_sprites | 3 | 最大携带数 |
| healing_per_sprite | 2 | 每个精灵回复的 HP |
| healing_burst_light_energy | 5.0 | 大爆炸释放的光照能量 |
| healing_burst_invincible_time | 0.2 | 大爆炸无敌时间（秒） |

---

## 7. 死亡清理

玩家死亡时：
```
Player._consume_all_healing_sprites_on_death():
  → 清空所有槽位
  → 调用每个精灵的 consume_on_death() 或 consume()
```
