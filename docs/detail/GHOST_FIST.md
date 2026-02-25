# GhostFist 功能逻辑与修复记录

> 更新时间：2026-02-26  
> 适用代码：`scene/weapons/ghost_fist/ghost_fist.gd`、`scene/components/player_animator.gd`、`scene/player.gd`、`scene/weapons/ghost_fist/ghost_fist.tscn`

---

## 1. 功能目标（正确逻辑）

GhostFist 是玩家的独立武器形态，核心由以下能力组成：

1. **独立状态机驱动**：`ENTER -> IDLE -> ATTACK_1..4 -> COOLDOWN -> IDLE`，并支持 `EXIT`。
2. **双手分离事件**：L/R 两个 Spine 节点分别发事件；命中/连击只接受主攻手。
3. **连击门控**：`combo_check` 时依据 `hit_confirmed + queued_next` 决定续段或收招。
4. **可见性能量系统**：通过光照/事件充能，`visible_time` 衰减决定实体化与透明度。
5. **摄魂与治愈精灵**：满足阈值触发摄魂 VFX，并在玩家未满上限时生成 HealingSprite。
6. **特殊目标命中**：既能打怪，也能命中 LightningFlower（不计入连击命中确认）。

---

## 2. 关键状态与手部规则

### 2.1 攻击主手映射（当前约定）

- `attack_1 -> LEFT`
- `attack_2 -> RIGHT`
- `attack_3 -> RIGHT`
- `attack_4 -> RIGHT`

这直接决定 `hit_on / hit_off / combo_check` 事件是否被接受。

### 2.2 连击判定规则

`combo_check` 到达时：

- 若 `hit_confirmed && queued_next`：进入下一段攻击。
- 否则：
  - `stage >= 3`：进入 `COOLDOWN`
  - `stage < 3`：直接回 `IDLE`（轻断连，不播 cooldown）

### 2.3 攻击完成兜底

若某段攻击动画结束但未收到 `combo_check`：

- `stage >= 3`：fallback 到 `COOLDOWN`
- `stage < 3`：fallback 到 `IDLE`

并且使用 `_combo_check_handled` 防止同一段被 `combo_check` 和 `animation_completed` 重复处理。

---

## 3. 动画事件契约（Spine 侧）

### 3.1 必须支持的事件名（大小写敏感）

- `hit_on`
- `hit_off`
- `combo_check`
- `z_front`
- `z_back`

### 3.2 事件归属原则

- 主攻手：允许 `hit_on/hit_off/combo_check`
- 副手：只放 z 事件（避免冗余日志和错误门控）

### 3.3 z-index 行为

- 激活时默认前景：`L=2`、`R=3`
- 攻击中由 `z_front/z_back` 动态切换
- 若某段后手层级异常，优先检查对应动画中是否缺失回位事件

---

## 4. 本次修复记录（本轮）

## 4.1 解决 Attack3 失败后 cooldown 被瞬间跳过

### 问题现象

`attack_3` 连击失败时，状态曾先进入 `COOLDOWN`，但随后被过期完成回调马上推进到 `IDLE`，视觉上表现为“看不到 cooldown”。

### 根因

处于 `GF_COOLDOWN` 时收到过期 completion（如 `attack_3`），`on_animation_complete()` 旧逻辑会直接执行 cooldown 完成转移。

### 修复

在 `GF_COOLDOWN` 分支增加 completion 门禁：

- 仅 `"ghost_fist_/cooldown"`（或空名兜底）允许将状态推进到 `IDLE`
- 非 cooldown 动画名在该状态下直接忽略

这保证了 attack3 fail 后 cooldown 不会被过期攻击 completion 抢跑。

## 4.2 既有稳定性改动（与本轮逻辑关联）

- `_on_gf_anim_complete` 对攻击态做“主攻手 + 动画名匹配/空名容错”过滤，避免旧段 completion 干扰新段。
- `_combo_check_handled` 标志用于防止同段 `combo_check` 与 `animation_completed` 重复推进。
- HealingSprite 生成前检查玩家容量，避免上限后仍持续实例化。

---

## 5. 调试建议

建议重点观察以下日志关键字：

- `combo_check ACCEPTED`
- `Combo broken ... entering cooldown`
- `Entering cooldown`
- `Cooldown completion ignored: anim=...`
- `Cooldown complete, now IDLE`

期望时序（attack3 fail）：

1. `combo_check ACCEPTED`（来自主攻手 R）
2. `Combo broken ... entering cooldown`
3. `Entering cooldown`
4. （可出现过期 completion）`Cooldown completion ignored: anim=ghost_fist_/attack_3`
5. cooldown 动画结束后：`Cooldown complete, now IDLE`

---

## 6. 相关文件

- `scene/weapons/ghost_fist/ghost_fist.gd`
- `scene/weapons/ghost_fist/ghost_fist.tscn`
- `scene/components/player_animator.gd`
- `scene/player.gd`

