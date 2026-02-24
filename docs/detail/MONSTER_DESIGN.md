# Monster Design（怪物设计文档）

本文档记录各类怪物的设计意图、行为规则和特殊机制，供开发和审计参考。

---

## 1. 锁链链接规则

怪物**必须处于虚弱(weak)或眩晕(stunned)状态**才能被锁链链接。
- `on_chain_hit()` 返回 1（可链接）的条件：`weak or stunned_t > 0.0`
- 返回 0 时扣血，不链接
- 奇美拉(Chimera)大多数可直接链接，不需要虚弱/眩晕前置

> **B6备注**: 这是核心设计，非Bug。链接=捕获，必须先削弱目标。

---

## 2. MonsterFly 显隐机制

MonsterFly 拥有可见性系统（`visible_time` / `visible_time_max`）：
- 隐身时 `collision_layer` 被清零（不可被锁链命中）
- **隐身时 `collision_mask` 保持不变**（防止穿透地形）

> **B10备注**: `collision_mask` 在隐身时保持是有意设计。如果清除mask，怪物会在隐身期间穿过地形，
> 变为可见时可能卡在墙里。保持mask确保物理碰撞一致性。

### 碰撞保存系统
MonsterFly 有两套碰撞保存：
1. **显隐专用**: `_saved_body_layer` / `_saved_body_mask`（MonsterFly自身管理）
2. **链接专用**: `_hurtbox_original_layer`（EntityBase/MonsterBase管理）

> **B2备注**: 两套系统独立运作，分别管理不同的碰撞域（body vs hurtbox），不存在冲突。

---

## 3. 治愈爆发(Healing Burst)机制

`healing_burst` 是**全场光照事件**，所有怪物都会收到：
- 通过 `EventBus.healing_burst` 信号广播
- 增加 `light_counter`（光照累积）
- 同时触发区域眩晕（`apply_healing_burst_stun`）

> **B5备注**: `light_energy + 1` 对所有怪物生效是正确行为。
> 治愈精灵释放自身能量时产生的环境光照效果，与属性无关。
> 眩晕效果通过Area2D碰撞检测，只影响范围内的怪物。

---

## 4. 虚弱状态流程

```
正常 → HP ≤ weak_hp → 虚弱(weak=true)
   ↓                        ↓
   ↓                   hp_locked=true
   ↓                   vanish_fusion_count=0
   ↓                   weak_stun_t = weak_stun_time
   ↓                        ↓
   ↓              weak_stun_t倒计时结束
   ↓                        ↓
   ↓              _restore_from_weak()
   ↓              hp=max_hp, weak=false
   ↓                        ↓
   └────────────────────────┘
```

- 虚弱期间可被锁链链接（核心玩法循环）
- 链接会延长虚弱眩晕时间（`weak_stun_extend_time`）
- MonsterBase._update_weak_state() 调用 super（EntityBase）后追加眩晕

---

## 5. 敌对怪物(MonsterHostile)

融合失败产物（`FAIL_HOSTILE` 结果）：
- `weak_hp = 0`，**永远不会进入虚弱状态**
- 被击杀后掉落治愈精灵
- 中型体型(`SizeTier.MEDIUM`)

> **B4备注**: 敌对怪物的AI行为（追踪玩家、主动攻击）属于计划功能，尚未实现。
> 当前仅有基础移动。

---

## 6. 奇美拉链接规则

奇美拉(Chimera)的链接行为与普通怪物不同：
- 大多数奇美拉**不需要虚弱/眩晕即可链接**（`on_chain_hit` 直接返回1）
- 链接后奇美拉跟随玩家
- 再次融合可产生更高级的奇美拉或触发特殊效果

> **A4备注**: 奇美拉的链接条件由各子类 `on_chain_hit()` 自行定义。
> ChimeraBase 默认允许直接链接。

---

## 7. entity_type 统一设置

所有怪物的 `entity_type = EntityType.MONSTER` 由 `MonsterBase._ready()` 统一设置。
子类**不需要**重复设置此值（R7优化）。

---

## 8. 计划功能标记

以下功能已预留接口但尚未实现：

| 标记 | 位置 | 说明 |
|------|------|------|
| D15 | `vanish_progress_updated` 信号 | 泯灭进度UI显示 |
| D16 | `light_finished` 信号 | 光照结束动画反馈 |
| D7 | `allow_move_interrupt_action` | 蓄力武器移动打断 |
| D14 | `add_rule/remove_rule/has_rule` | 运行时配方解锁系统 |
| D11 | `setup(player)` / `set_player(player)` | 奇美拉显式注入player引用 |
